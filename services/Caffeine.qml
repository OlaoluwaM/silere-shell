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

    // presetLabel/presets drive the duration picker; a run started with 0 never expires
    // on its own, matching toggle()'s pre-existing plain start/stop
    function _sanitizePresets(raw: string): var {
        const parts = String(raw || "").split(",")
        const seen = ({})
        const out = []
        for (let i = 0; i < parts.length; i++) {
            const t = parts[i].trim()
            if (!/^\d+$/.test(t)) continue
            const n = parseInt(t, 10)
            if (seen[n]) continue
            seen[n] = true
            out.push(n)
        }
        // "until turned off" must always be selectable even if the packaged list omits it
        if (!seen[0]) out.push(0)
        return out
    }
    readonly property var presets: root._sanitizePresets(ShellSettings.caffeinePresets)

    function presetLabel(minutes: int): string {
        if (minutes <= 0) return "Until turned off"
        if (minutes < 60) return minutes + "m"
        if (minutes % 60 === 0) return (minutes / 60) + "h"
        return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m"
    }

    // the unit is packaged as "<name>.service"; the transient stop timer rides beside
    // it under "<name>-stop" so `systemctl --user list-timers` reads as one obvious pair
    readonly property string _unitStem: root.unit.replace(/\.service$/, "")
    readonly property string _stopTimer: root._unitStem + "-stop.timer"

    function toggle(): void {
        if (!available || _toggleProc.running) return
        const goingOn = !root.manualActive
        root.lastError = ""
        // optimistic: the row/pill flips the moment it's tapped, and _checkActive
        // (run from the chain's tail below) reconciles it with the unit if the call failed
        root.manualActive = goingOn
        if (goingOn) root._startTimed(ShellSettings.caffeinePreset)
        else root._stopTimed()
    }

    // called when the picker changes the duration while caffeine is already on: the
    // running unit is left alone, only the scheduled stop is replaced
    function selectPreset(minutes: int): void {
        ShellSettings.caffeinePreset = minutes
        if (!root.manualActive || !root.available) return
        // a chain (toggle-on, or an earlier reschedule) is already mid-flight: queue
        // this one rather than dropping it, same as _recheckPending queues a
        // reconciliation that arrived while _checkProc was already running
        if (_toggleProc.running) { root._pendingPresetMinutes = minutes; return }
        root._startTimed(minutes)
    }

    // -1 is "nothing queued": a real preset is always >= 0
    property int _pendingPresetMinutes: -1

    // a plain QML Timer would die with the shell (crash, logout, `systemctl restart`
    // on the shell unit) and leave caffeine pinned on forever; a transient systemd-run
    // timer survives the shell and fires even if nothing is left to hear it.
    //
    // Replace-before-run: a stale timer from an earlier run (a shorter preset, or a
    // manual restart) must be cleared before scheduling the new one, or the old one
    // fires early and stops the unit out from under the new run. --collect makes
    // systemd-run also GC the transient unit itself once it fires, instead of it
    // sitting around as a dead unit forever.
    function _startTimed(minutes: int): void {
        const commands = [
            { args: ["systemctl", "--user", "stop", root._stopTimer], ignoreFailure: true }
        ]
        if (minutes > 0) {
            commands.push({
                args: ["systemd-run", "--user", "--collect", "--unit=" + root._unitStem + "-stop",
                    "--on-active=" + minutes + "m", "systemctl", "--user", "stop", root.unit],
                ignoreFailure: false
            })
        }
        commands.push({ args: ["systemctl", "--user", "start", root.unit], ignoreFailure: false })
        root._runChain(commands)
    }

    function _stopTimed(): void {
        root._runChain([
            { args: ["systemctl", "--user", "stop", root.unit], ignoreFailure: false },
            { args: ["systemctl", "--user", "stop", root._stopTimer], ignoreFailure: true }
        ])
    }

    // small state machine over BoundedProcess: each command runs to completion before
    // the next is spawned (systemd-run must land before the plain start races it), and
    // a hard failure aborts the rest of the chain rather than leaving it half-applied.
    // BoundedProcess's own timeout window doesn't restart between chained exec() calls
    // (it watches `running`, which never observably drops between chain steps), so the
    // 5s budget is really shared across the whole chain, not per command. Every command
    // here is a local `systemctl --user`/`systemd-run --user` call with no network or
    // polkit prompt involved, so that shared budget is generous in practice.
    property var _chainQueue: []
    property bool _chainIgnoreCurrent: false

    function _runChain(commands: var): void {
        if (commands.length === 0) { root._checkActive(); root._checkInhibitors(); root._pollRemaining(); return }
        root._chainQueue = commands.slice(1)
        const first = commands[0]
        root._chainIgnoreCurrent = first.ignoreFailure === true
        _toggleProc.exec(first.args)
    }

    // a check already in flight when a reconciliation is requested would otherwise
    // just drop it; queue it instead so a post-toggle recheck is never lost
    property bool _recheckPending: false

    function _checkActive(): void {
        if (!root.available) return
        if (_checkProc.running) { root._recheckPending = true; return }
        _checkProc.exec(["systemctl", "--user", "is-active", "--quiet", root.unit])
    }

    Component.onCompleted: { root._checkActive(); root._checkInhibitors(); root._pollRemaining() }

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
            const failed = _toggleProc.timedOut || code !== 0
            if (failed && !root._chainIgnoreCurrent) {
                // a hard failure mid-chain (systemd-run rejected, unit missing, ...)
                // abandons the rest of the chain rather than starting a unit whose
                // scheduled stop never got armed, or leaving a stop-timer stray
                root.lastError = _toggleErr.text.trim().split("\n").pop() || (root.unit + " did not respond")
                root._chainQueue = []
                // a reschedule queued against the chain that just failed would otherwise
                // fire against unknown state once the chain frees up
                root._pendingPresetMinutes = -1
                root._checkActive()
                root._checkInhibitors()
                root._pollRemaining()
                return
            }
            if (root._chainQueue.length > 0) {
                const remaining = root._chainQueue
                const next = remaining[0]
                root._chainQueue = remaining.slice(1)
                root._chainIgnoreCurrent = next.ignoreFailure === true
                _toggleProc.exec(next.args)
                return
            }
            // a preset picked while this chain was already running (selectPreset queued
            // it instead of dropping it): run it now instead of reconciling first, since
            // it immediately supersedes whatever this chain just armed
            if (root._pendingPresetMinutes >= 0) {
                const nextPreset = root._pendingPresetMinutes
                root._pendingPresetMinutes = -1
                if (root.manualActive) { root._startTimed(nextPreset); return }
            }
            // chain finished: reconcile with the unit, same as toggle() always did
            root._checkActive()
            // reflects our own flip in the shared inhibitor list immediately, rather
            // than waiting out the rest of the poll interval below
            root._checkInhibitors()
            // ditto for the readout: without this a fresh timed run (or a preset swap
            // mid-run) shows the old/no countdown for up to 15s after the chain lands
            root._pollRemaining()
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
        onTriggered: { root._checkInhibitors(); root._pollRemaining() }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (!Idle.isIdle && root.available) { root._checkInhibitors(); root._pollRemaining() }
        }
    }

    property int _remainingMinutes: -1
    // -1 covers both "not timed" and "unknown": the row falls back to a plain "On",
    // which is also the right thing to show for a run that has no stop scheduled
    readonly property int remainingMinutes: root._remainingMinutes

    // rides the inhibitor poll's cadence instead of a timer of its own — this only
    // needs to be as fresh as the row that reads it, and that row is already stale
    // for up to 15s on the inhibitor side
    //
    // `systemctl show <timer> --property=NextElapseUSecRealtime --value` reads empty
    // for this timer: --on-active= schedules on the *monotonic* clock, and systemd
    // only publishes a realtime estimate for that schedule through `list-timers`'
    // NEXT column, not as a queryable property (verified directly: NextElapseUSecReal-
    // time is blank, NextElapseUSecMonotonic prints raw monotonic offsets with no
    // portable way to relate them to wall time from here). list-timers' NEXT column
    // is the same absolute timestamp shape, so it's what gets parsed below instead.
    function _pollRemaining(): void {
        if (!root.available || !root.manualActive) { root._remainingMinutes = -1; return }
        if (_remainingProc.running) return
        _remainingProc.exec(["systemctl", "--user", "list-timers", root._stopTimer, "--no-legend"])
    }

    BoundedProcess {
        id: _remainingProc
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _remainingOut }
        onExited: (code) => {
            const wasTimed = root._remainingMinutes >= 0
            // C locale fixes the timestamp shape systemd prints (e.g. "Thu 2024-05-02
            // 14:00:00 UTC"); pulling the date+time out by pattern rather than trusting
            // token positions survives the weekday/timezone fields shifting around it.
            // A gone/elapsed timer prints nothing at all (--no-legend leaves no header
            // to fall back on), which the same "no match" branch below already covers.
            const m = (!_remainingProc.timedOut && code === 0)
                ? /(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})/.exec(_remainingOut.text)
                : null
            // no match covers both "n/a" (no timer scheduled: an untimed run) and a
            // process failure; either way there is nothing to count down
            if (!m) {
                root._remainingMinutes = -1
                if (wasTimed) root._checkActive()
                return
            }
            const target = new Date(m[1] + "T" + m[2])
            const diffMs = target.getTime() - Date.now()
            // <=0 means the timer already fired but the unit hasn't been reaped from
            // is-active yet — treat it as gone now instead of waiting for the next poll
            if (!isFinite(target.getTime()) || diffMs <= 0) {
                root._remainingMinutes = -1
                if (wasTimed) root._checkActive()
                return
            }
            root._remainingMinutes = Math.ceil(diffMs / 60000)
        }
    }

    // the Nix-side hypr-shell-caffeine script backing the Super+C chord calls this
    // first (`qs ipc call caffeine toggle`) so a chord press goes through the same
    // preset-aware toggle() the row uses — reading ShellSettings.caffeinePreset and
    // updating the UI immediately — instead of a raw `systemctl` that would start an
    // untimed run and leave the row unaware until the next drift poll. The script
    // falls back to raw systemctl only when the shell itself isn't up to answer IPC.
    IpcHandler {
        target: "caffeine"
        function toggle(): void { if (root.available) root.toggle() }
    }
}
