pragma Singleton

// Ownership split: a Nix-managed `hypr-shell-caffeine.service` systemd user unit is a
// bare `systemd-inhibit --what=idle ... --mode=block sleep infinity` wrapper — the same
// "shell only starts/stops the unit and mirrors its state" control surface NightLight
// uses for hyprsunset.service. This singleton never spawns or holds an inhibitor itself.
//
// The pill and menu row also care about idle being blocked by anything, not just our
// own unit, so this additionally tracks `systemd-inhibit --list` output. logind only
// knows about inhibitors taken out through its own D-Bus/CLI surface: a Wayland client
// blocking idle straight through the zwp_idle_inhibit_manager_v1 protocol never
// registers with logind and stays invisible to this check. `inhibited` therefore means
// "logind reports a block-mode idle inhibitor", not "nothing is keeping the session
// awake" — some protocol-only inhibitors will never light the pill.
//
// logind does emit a change signal for the inhibitor list after all: it re-publishes
// its own BlockInhibited property (via org.freedesktop.DBus.Properties.PropertiesChanged
// on /org/freedesktop/login1) whenever a block-mode inhibitor is taken or released. A
// `dbus-monitor` watcher below listens for that and reconciles immediately when it
// fires, so the 15s poll further down only exists as the fallback for a system without
// dbus-monitor, or for the gap while the watcher itself is down/restarting.

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    readonly property string unit: ShellSettings.caffeineUnit
    readonly property bool available: unit.length > 0 && SystemTools.hasSystemctl

    property bool manualActive: false
    property string lastError: ""

    property bool inhibited: false
    property string inhibitorLabel: ""

    // the duration picker itself lives in DurationPickerColumn, which sanitizes
    // caffeinePresets on its own; a run started with 0 never expires on its own,
    // matching toggle()'s pre-existing plain start/stop

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
        if (goingOn) {
            root._startTimed(ShellSettings.caffeinePreset)
        } else {
            // the inhibitor ghost goes optimistically too: our own unit sits in the
            // shared list until the stop chain lands and the recheck returns, and
            // for those frames the row's status fell through to the "foreign
            // inhibitor" branch and flashed our own WHO between the countdown and
            // "Off". A real foreign inhibitor comes back with the chain-tail recheck.
            root.inhibited = false
            root.inhibitorLabel = ""
            root._stopTimed()
        }
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
    // the duration the in-flight chain is arming, committed into _stopDeadlineMs
    // only when that chain lands; -1 when no arm is in flight
    property int _armedMinutes: -1

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
        // remembered, not yet believed: the deadline mirror commits only when the
        // chain below lands, so a failed arm never shows a countdown for a stop
        // that was never scheduled
        root._armedMinutes = minutes
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
        root._armedMinutes = -1
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
                // the run was just discovered here rather than armed by us (a shell
                // restarted mid-run, or an external re-arm the drift poll caught) --
                // no chain tail ever ran to commit a deadline, so ask systemd for one
                if (root.manualActive && root._stopDeadlineMs <= 0 && root._armedMinutes < 0 && !_toggleProc.running) {
                    root._pollRemaining()
                }
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
                // ditto the uncommitted deadline: whatever this chain was arming is
                // now unknown, so ask systemd instead of believing it
                root._armedMinutes = -1
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
            // the shell armed this stop itself, so the deadline is knowledge rather
            // than something to ask systemd for: commit the local mirror and let its
            // tick carry the countdown from here. Gated on the same invariant
            // _syncRemaining enforces -- a drift check that reported inactive
            // mid-chain must not park a deadline against a run the mirror thinks is
            // off (the chain-tail _checkActive below rediscovers it, and discovery
            // refills the mirror through the reconciler)
            if (root._armedMinutes >= 0) {
                root._stopDeadlineMs = root.manualActive && root._armedMinutes > 0
                    ? Date.now() + root._armedMinutes * 60000 : 0
                root._armedMinutes = -1
            }
            root._syncRemaining()
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

    // dbus-monitor below reconciles on every real change; while it's up this only needs
    // to catch what it might miss (a signal dropped between a crash and its respawn), so
    // it stretches out to 120s. Without it (tool absent, or the watcher unit down) this
    // is the only thing driving `inhibited` at all, so it holds the original 15s. Paused
    // while idle since nothing is watching the pill then, and re-armed the instant the
    // session goes active again below.
    readonly property bool _watcherHealthy: SystemTools.hasDbusMonitor && _inhibitWatcher.running
    Timer {
        interval: root._watcherHealthy ? 120000 : 15000
        repeat: true
        running: root.available && !Idle.isIdle
        onTriggered: root._checkInhibitors()
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (!Idle.isIdle && root.available) root._checkInhibitors()
        }
    }

    // event-driven half of the inhibitor check: logind republishes BlockInhibited on
    // /org/freedesktop/login1 through the standard Properties.PropertiesChanged signal
    // whenever a block-mode inhibitor is taken or released, so watching that line up
    // reconciles immediately instead of waiting out the poll above. Not gated on Idle —
    // an inhibitor change while idle still matters for state correctness once the
    // session wakes, and events are rare enough that watching through idle costs nothing.
    //
    // command stays a plain constant, not a function of _watcherHealthy or anything else
    // superviseWhen depends on, for the same reason Recording.qml's watcher does: gating
    // command on the same condition that flips superviseWhen would race two independent
    // bindings off the same signal. superviseWhen alone decides whether this ever runs.
    //
    // dbus-monitor prints a connection preamble (NameAcquired and friends) before any
    // real signal; those lines never contain "BlockInhibited" so the substring check
    // below just ignores them.
    SupervisedProcess {
        id: _inhibitWatcher
        superviseWhen: root.available && SystemTools.hasDbusMonitor
        restartDelay: 5000
        command: ["dbus-monitor", "--system",
            "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/freedesktop/login1'"]
        stdout: SplitParser {
            onRead: line => { if (line.indexOf("BlockInhibited") >= 0) root._checkInhibitors() }
        }
        // reconciles any gap opened by a crash/restart cycle the instant the watcher is
        // back, same restat-on-restart idiom Recording.qml's inotifywait watcher uses
        onRunningChanged: if (running) root._checkInhibitors()
    }

    // the countdown's source of truth for display: an epoch-ms mirror of the stop
    // timer's deadline, committed locally when this shell arms the timer itself and
    // refilled from systemd by the reconciler below for runs it did not start (a
    // shell restarted mid-run) or no longer owns (a manual systemctl re-arm). Not
    // persisted on purpose -- after a restart the reconciler is the honest source.
    property double _stopDeadlineMs: 0
    property int _remainingMinutes: -1
    // -1 covers both "not timed" and "unknown": the row falls back to a plain "On",
    // which is also the right thing to show for a run that has no stop scheduled
    readonly property int remainingMinutes: root._remainingMinutes

    function _syncRemaining(): void {
        if (!root.manualActive || !(root._stopDeadlineMs > 0)) {
            root._remainingMinutes = -1
            return
        }
        const diffMs = root._stopDeadlineMs - Date.now()
        if (diffMs <= 0) {
            // a passed deadline only stops the display here, not proves the run
            // over: --on-active schedules on the monotonic clock (paused across
            // suspend) while this mirror is wall-clock, so a deadline that
            // "passed" during sleep can really still be ahead. Ask both sides:
            // is-active reaps a genuinely finished run (the deadline is already
            // zeroed, so the poll's own no-match branch would skip that check),
            // and list-timers refills one merely slept through with the true
            // deadline systemd re-projects onto the realtime clock.
            root._stopDeadlineMs = 0
            root._remainingMinutes = -1
            root._checkActive()
            root._pollRemaining()
            return
        }
        root._remainingMinutes = Math.ceil(diffMs / 60000)
    }

    onManualActiveChanged: {
        if (!root.manualActive) root._stopDeadlineMs = 0
        root._syncRemaining()
    }

    // display cadence, idle-gated unlike DND's tick: there the deadline enforces the
    // state itself, here systemd fires the actual stop, so this is presentation only
    // and can sleep with the session -- triggeredOnStart snaps it current on wake
    Timer {
        interval: 30000
        repeat: true
        running: root.manualActive && root._stopDeadlineMs > 0 && !Idle.isIdle
        triggeredOnStart: true
        onTriggered: root._syncRemaining()
    }

    // The reconciler: asks systemd for the stop timer's next elapse and refills the
    // mirror from it. Runs wherever a deadline is unknown and someone is actually
    // about to read the number -- is-active discovering a run with no committed
    // deadline (a shell restarted mid-run, or the drift poll catching an external
    // re-arm), chain failures, the pill's expanding hover label, the menu's home
    // page opening -- instead of on a periodic cadence the mirror made redundant.
    //
    // `systemctl show <timer> --property=NextElapseUSecRealtime --value` reads empty
    // for this timer: --on-active= schedules on the *monotonic* clock, and systemd
    // only publishes a realtime estimate for that schedule through `list-timers`'
    // NEXT column, not as a queryable property (verified directly: NextElapseUSecReal-
    // time is blank, NextElapseUSecMonotonic prints raw monotonic offsets with no
    // portable way to relate them to wall time from here). list-timers' NEXT column
    // is the same absolute timestamp shape, so it's what gets parsed below instead.
    function _pollRemaining(): void {
        if (!root.available || !root.manualActive) { root._syncRemaining(); return }
        if (_remainingProc.running) return
        // a toggle or arm in flight will land its own authoritative deadline at the
        // chain tail; a poll started now would just race it for a stale answer, and
        // a dropped poll costs nothing since the chain tail always follows up
        if (_toggleProc.running || root._armedMinutes >= 0) return
        _remainingProc.exec(["systemctl", "--user", "list-timers", root._stopTimer, "--no-legend"])
    }

    // the widget-facing nudge (same name style as Notifications.refreshFullscreenState):
    // the pill calls this as its hover label expands, the row's page-open hook below
    // does the same. The in-flight guard in _pollRemaining rate-limits repeats.
    //
    // Deliberately NOT skipped while the mirror already holds a deadline: the stop
    // timer is an ordinary transient user unit anyone can replace or cancel with a
    // raw systemctl/systemd-run behind the shell's back, and systemd pushes no
    // signal when that happens -- asking on every look is what keeps the hover
    // label truthful against it, at the cost of one local list-timers per glance.
    function refreshRemaining(): void { root._pollRemaining() }

    // the menu row reads the countdown whenever the home page is up, so entering it
    // is that row's "hover"
    Connections {
        target: MenuState
        function onHomeActiveChanged() {
            if (MenuState.homeActive && root.manualActive) root._pollRemaining()
        }
    }

    BoundedProcess {
        id: _remainingProc
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _remainingOut }
        onExited: (code) => {
            // a result that raced a toggle or an arm is stale by definition -- the
            // chain tail is the authoritative source for this run now, so touch
            // nothing and let it land instead
            if (!root.manualActive || _toggleProc.running || root._armedMinutes >= 0) return
            const wasTimed = root._stopDeadlineMs > 0
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
                root._stopDeadlineMs = 0
                root._syncRemaining()
                if (wasTimed) root._checkActive()
                return
            }
            const target = new Date(m[1] + "T" + m[2])
            const diffMs = target.getTime() - Date.now()
            // <=0 means the timer already fired but the unit hasn't been reaped from
            // is-active yet — treat it as gone now instead of waiting for the next poll
            if (!isFinite(target.getTime()) || diffMs <= 0) {
                root._stopDeadlineMs = 0
                root._syncRemaining()
                if (wasTimed) root._checkActive()
                return
            }
            root._stopDeadlineMs = target.getTime()
            root._syncRemaining()
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
