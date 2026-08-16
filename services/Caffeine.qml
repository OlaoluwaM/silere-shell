pragma Singleton

// Ownership split: a Nix-managed `hypr-shell-caffeine.service` systemd user unit is a
// bare `systemd-inhibit --what=idle ... --mode=block sleep infinity` wrapper — the same
// "shell only starts/stops the unit and mirrors its state" control surface NightLight
// uses for hyprsunset.service. This singleton never spawns or holds an inhibitor itself.
//
// The pill and menu row also care about idle being blocked by anything, not just our
// own unit, so this additionally polls `systemd-inhibit --list` on a timer. logind only
// knows about inhibitors taken out through its own D-Bus/CLI surface: a Wayland client
// blocking idle straight through the zwp_idle_inhibit_manager_v1 protocol never
// registers with logind and stays invisible to this poll. `inhibited` therefore means
// "logind reports a block-mode idle inhibitor", not "nothing is keeping the session
// awake" — some protocol-only inhibitors will never light the pill.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string unit: ShellSettings.caffeineUnit
    readonly property bool available: unit.length > 0 && SystemTools.hasSystemctl

    property bool manualActive: false
    property string lastError: ""

    property bool inhibited: false
    property string inhibitorLabel: ""

    function toggle(): void {
        if (!available || _toggleProc.running) return
        const goingOn = !root.manualActive
        root.lastError = ""
        // optimistic: the row/pill flips the moment it's tapped, and _checkActive
        // (run from onExited below) reconciles it with the unit if the call failed
        root.manualActive = goingOn
        _toggleProc.exec(["systemctl", "--user", goingOn ? "start" : "stop", root.unit])
    }

    // a check already in flight when a reconciliation is requested would otherwise
    // just drop it; queue it instead so a post-toggle recheck is never lost
    property bool _recheckPending: false

    function _checkActive(): void {
        if (!root.available) return
        if (_checkProc.running) { root._recheckPending = true; return }
        _checkProc.exec(["systemctl", "--user", "is-active", "--quiet", root.unit])
    }

    Component.onCompleted: { root._checkActive(); root._checkInhibitors() }

    Connections {
        target: SystemTools
        function onReadyChanged() { root._checkActive(); root._checkInhibitors() }
    }

    BoundedProcess {
        id: _checkProc
        timeoutMs: 5000
        onExited: (code) => {
            const rerun = root._recheckPending
            root._recheckPending = false
            if (_checkProc.timedOut) {
                root.lastError = "could not check " + root.unit
            } else {
                root.manualActive = (code === 0)
            }
            if (rerun) root._checkActive()
        }
    }

    BoundedProcess {
        id: _toggleProc
        timeoutMs: 5000
        stderr: StdioCollector { id: _toggleErr }
        onExited: (code) => {
            if (_toggleProc.timedOut || code !== 0)
                root.lastError = _toggleErr.text.trim().split("\n").pop() || (root.unit + " did not respond")
            root._checkActive()
            // reflects our own flip in the shared inhibitor list immediately, rather
            // than waiting out the rest of the poll interval below
            root._checkInhibitors()
        }
    }

    // catches drift from outside the shell (a manual systemctl call, the unit
    // failing on its own) since only systemd — not this singleton — decides
    // when the unit actually starts or stops
    Timer {
        interval: 60000; repeat: true
        running: root.available
        onTriggered: root._checkActive()
    }

    property bool _inhibitCheckPending: false

    function _checkInhibitors(): void {
        if (!root.available) return
        if (_inhibitProc.running) { root._inhibitCheckPending = true; return }
        _inhibitProc.exec(["systemd-inhibit", "--list", "--no-legend", "--mode=block"])
    }

    // `systemd-inhibit --list` is a fixed-width table (WHO UID USER PID COMM WHAT WHY
    // MODE) whose column widths — and even column order — have shifted across systemd
    // releases, and WHO/WHY can themselves contain spaces ("Realtime Kit"). Splitting on
    // whitespace and anchoring on the first purely-numeric token (UID, which nothing
    // else in the row can be confused for) survives that better than trusting fixed
    // column offsets: everything left of it is WHO, and WHAT/WHY sit at fixed offsets
    // from there since UID/USER/PID/COMM/WHAT never contain embedded spaces. Requiring
    // the token two places later (PID) to also be numeric before accepting the anchor
    // keeps a stray digit inside a multi-word WHO ("Session 2 login") from being read
    // as the UID and shifting every field after it.
    function _parseIdleInhibitors(text: string): var {
        const lines = String(text || "").split(/\r?\n/)
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const trimmed = lines[i].trim()
            if (trimmed.length === 0) continue
            const tokens = trimmed.split(/\s+/)
            let uidIdx = -1
            for (let t = 0; t < tokens.length; t++) {
                if (/^\d+$/.test(tokens[t]) && /^\d+$/.test(tokens[t + 2] || "")) { uidIdx = t; break }
            }
            // uid, user, pid, comm, what, then at least the trailing mode column
            if (uidIdx < 1 || tokens.length < uidIdx + 6) continue
            const what = tokens[uidIdx + 4]
            if (!/(^|:)idle(:|$)/.test(what)) continue
            const who = tokens.slice(0, uidIdx).join(" ")
            out.push(SafeText.singleLineText(who, 64))
        }
        return out
    }

    BoundedProcess {
        id: _inhibitProc
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _inhibitOut }
        onExited: (code) => {
            const rerun = root._inhibitCheckPending
            root._inhibitCheckPending = false
            if (!_inhibitProc.timedOut && code === 0) {
                const who = root._parseIdleInhibitors(_inhibitOut.text)
                root.inhibited = who.length > 0
                root.inhibitorLabel = who.length === 0 ? ""
                    : who.length === 1 ? who[0]
                    : who.length + " inhibitors"
            }
            if (rerun) root._checkInhibitors()
        }
    }

    // logind exposes no change signal for the inhibitor list, so this is poll-only;
    // paused while idle since nothing is watching the pill then, and re-armed the
    // instant the session goes active again below
    Timer {
        interval: 15000; repeat: true
        running: root.available && !Idle.isIdle
        onTriggered: root._checkInhibitors()
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (!Idle.isIdle && root.available) root._checkInhibitors()
        }
    }
}
