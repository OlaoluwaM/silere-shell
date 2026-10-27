pragma Singleton

import QtQuick
import Quickshell
import "../../services"
import "../../config"
import "../../services/PowerActions.js" as PowerActions

// Suspend, Reboot and Power off from the lock screen. The lock drives its own countdown
// rather than borrowing the desktop's PowerActionState: that one belongs to the shell's
// process and refuses to open while the session is idle, which is exactly when hypridle
// locks. Reboot and Power off wait out the same 60s as the desktop card, with nothing run
// until it ends; Suspend runs at once.
//
// The commands are plain systemctl, not Settings.rebootCommand/poweroffCommand: those go
// through hyprshutdown, which closes every app first and lets one with unsaved work hold the
// shutdown behind the lock, where its prompt cannot be reached.
Singleton {
    id: root

    // false until lock.qml says this is a real lock the wrapper started. Anything else (the
    // preview, a sandboxed run) runs a stand-in instead of systemctl: `true`, or `false` when
    // SILERE_LOCK_PREVIEW_POWER=fail, so the failure card can be designed without a failure
    property bool live: false

    readonly property int seconds: 60
    // "" when closed, then "menu", "countdown", "running" or "failed"; written only here, so
    // every transition goes through the guards below
    property string _stage: ""
    readonly property string stage: root._stage
    readonly property bool open: root._stage.length > 0
    property string _kind: ""
    property int _remaining: 0
    property real _deadline: 0
    property real _lastTick: 0
    property real _countdownAtMs: 0
    readonly property string kind: root._kind
    readonly property int remaining: root._remaining
    // the card's bar drains toward the wall-clock end, the one clock the seconds also read
    readonly property real deadline: root._deadline
    // kept through close so the card's exit fade still reads the action it was showing
    readonly property var action: root.actions[root._kind] ?? null

    // the desktop card's words and glyphs, from the table both read
    readonly property var actions: PowerActions.table(["suspend", "reboot", "poweroff"])

    signal started()

    function openMenu(): void {
        if (root.open || LockState.unlocking || LockState.checking) return
        root._stage = "menu"
    }

    // Esc and a tap outside: every way out short of confirming, except while a command runs,
    // since by then there is nothing left to take back
    function dismiss(): void {
        if (root.stage === "running") return
        root._stage = ""
    }

    // only from the open menu: its tiles stay on screen through the card's exit fade, and a tap
    // there after Esc must not start an action the user just walked away from
    function pick(kind: string): void {
        if (root.stage !== "menu" || LockState.unlocking) return
        // a plain object also answers inherited names such as "toString"
        if (!Object.prototype.hasOwnProperty.call(root.actions, kind)) return
        root._kind = kind
        console.info(LockState.log, "silere-shell: power action picked:", kind)
        if (kind === "suspend") {
            root._run()
            return
        }
        root._remaining = root.seconds
        root._deadline = Date.now() + root.seconds * 1000
        root._lastTick = Date.now()
        root._countdownAtMs = Date.now()
        root._stage = "countdown"
        root.started()
    }

    function confirm(): void {
        if (root.stage !== "countdown") return
        root._run()
    }

    // the countdown's confirm button opens under the tile that started it, so the second click
    // of a double-click would run the action the countdown exists to give a chance to cancel;
    // Enter is a deliberate key and keeps going through confirm()
    function confirmByPointer(): void {
        if (Date.now() - root._countdownAtMs < Metrics.confirmGuardMs) return
        root.confirm()
    }

    function retry(): void {
        if (root.stage === "failed") root._run()
    }

    function _run(): void {
        // the unlock ends every stage; a command that slipped in after it would outlive the lock
        if (LockState.unlocking) return
        // --no-ask-password: polkit's prompt would open on the desktop behind the lock, where
        // nobody can answer it, and systemctl would wait on it with the card stuck running
        const command = root.live ? ["systemctl", "--no-ask-password", root._kind]
            : [Quickshell.env("SILERE_LOCK_PREVIEW_POWER") === "fail" ? "false" : "true"]
        if (!root.live)
            console.info(LockState.log, "silere-shell: not a live lock;", command[0],
                "stands in for systemctl", root._kind)
        root._stage = "running"
        _proc.exec(command)
    }

    BoundedProcess {
        id: _proc
        // logind answers at once, whether it queues the job or refuses it; a systemctl still
        // running after this is stuck, and the field must not stay out of reach behind it.
        // The timer is monotonic, so the time a suspend spends asleep does not count
        timeoutMs: 30000
        // a failed start never reports an exit on its own; BoundedProcess turns it into 127
        onExited: (code) => {
            const ok = _proc.completedSuccessfully(code)
            const report = "silere-shell: power action " + root._kind + " exited with " + code
                + (_proc.timedOut ? " after timing out" : "")
            if (ok) console.info(LockState.log, report)
            else console.warn(LockState.log, report)
            if (root.stage !== "running") return
            if (!ok) {
                root._stage = "failed"
            } else if (root._kind === "suspend" || !root.live) {
                // logind queues a suspend and answers before the machine sleeps, so the card
                // closes and the machine wakes to the lock it left; a stand-in has nothing to
                // bring down
                root._stage = ""
            } else {
                _goingDown.start()
            }
        }
    }

    // a reboot or power off that logind accepted keeps the card up while the session goes
    // down; one that never comes must not leave the lock without its field
    Timer {
        id: _goingDown
        interval: 60000
        onTriggered: {
            if (root.stage !== "running") return
            console.warn(LockState.log, "silere-shell: power action", root._kind,
                "was accepted, but the session is still up a minute later")
            root._stage = "failed"
        }
    }

    // unlocking ends any countdown: nothing may fire on a desktop that left the lock behind
    Connections {
        target: LockState
        function onUnlockingChanged() { if (LockState.unlocking) root.dismiss() }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.stage === "countdown"
        onTriggered: {
            const now = Date.now()
            const late = now - root._lastTick
            root._lastTick = now
            // a tick this late means the machine slept through the countdown; nobody was
            // there to cancel it, so it must not fire on wake
            if (late > 2000) {
                console.info(LockState.log, "silere-shell: power countdown slept through; cancelled")
                root.dismiss()
                return
            }
            const left = root._deadline - now
            if (left <= 0) {
                root.confirm()
                return
            }
            root._remaining = Math.ceil(left / 1000)
        }
    }
}
