pragma Singleton

import QtQuick
import Quickshell
import "../../services"

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
    // "" when closed, then "menu", "countdown", "running" or "failed"
    property string stage: ""
    readonly property bool open: root.stage.length > 0
    property string _kind: ""
    property int _remaining: 0
    property real _deadline: 0
    property real _lastTick: 0
    readonly property string kind: root._kind
    readonly property int remaining: root._remaining
    // the card's bar drains toward the wall-clock end, the one clock the seconds also read
    readonly property real deadline: root._deadline
    // kept through close so the card's exit fade still reads the action it was showing
    readonly property var action: root.actions[root._kind] ?? null

    // the desktop card's words and glyphs, so the two read the same
    readonly property var actions: ({
        suspend:  { label: "Suspend",   glyph: "󰒲", phrase: "Suspending",   failTitle: "Suspend failed" },
        reboot:   { label: "Reboot",    glyph: "󰑐", phrase: "Rebooting",    failTitle: "Reboot failed" },
        poweroff: { label: "Power off", glyph: "󰐥", phrase: "Powering off", failTitle: "Shut down failed" }
    })

    signal started()

    function openMenu(): void {
        if (root.stage === "running" || LockState.unlocking) return
        root.stage = "menu"
    }

    // Esc and a tap outside: every way out short of confirming, except while a command runs,
    // since by then there is nothing left to take back
    function dismiss(): void {
        if (root.stage === "running") return
        root.stage = ""
    }

    // a plain object also answers inherited names such as "toString"
    function pick(kind: string): void {
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
        root.stage = "countdown"
        root.started()
    }

    function confirm(): void {
        if (root.stage !== "countdown") return
        root._run()
    }

    function retry(): void {
        if (root.stage === "failed") root._run()
    }

    function _run(): void {
        const command = root.live ? ["systemctl", root._kind]
            : [Quickshell.env("SILERE_LOCK_PREVIEW_POWER") === "fail" ? "false" : "true"]
        if (!root.live)
            console.info(LockState.log, "silere-shell: not a live lock;", command[0],
                "stands in for systemctl", root._kind)
        root.stage = "running"
        _proc.exec(command)
    }

    BoundedProcess {
        id: _proc
        // a failed start never reports an exit on its own; BoundedProcess turns it into 127
        onExited: (code) => {
            const ok = code === 0
            const report = "silere-shell: power action " + root._kind + " exited with " + code
            if (ok) console.info(LockState.log, report)
            else console.warn(LockState.log, report)
            if (root.stage !== "running") return
            // a suspend returns once the machine wakes, back to the lock it left; a reboot or
            // power off that succeeded leaves the card up until the session goes down
            if (!ok) root.stage = "failed"
            else if (root._kind === "suspend") root.stage = ""
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
