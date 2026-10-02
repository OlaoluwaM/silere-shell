pragma Singleton

import QtQuick
import Quickshell
import "../config"

// State for PowerActionCard (modules/power). Log out, Reboot and Power off run behind a
// countdown on a centered card, and the countdown is the confirmation: nothing has run
// until it ends, and every way out of the card short of confirming cancels with nothing to
// undo. The countdown lives here rather than on the card because the card is a lazily
// loaded surface that may not exist yet when the countdown starts.
PopupState {
    id: root

    readonly property int seconds: 10
    property string _kind: ""
    property int _remaining: 0
    property real _deadline: 0
    readonly property string kind: _kind
    readonly property int remaining: _remaining
    // the drain reads the wall-clock end so a card created after the request starts
    // part-way through instead of from full
    readonly property real deadline: _deadline
    // kept through close so the card's exit fade still reads the action it was showing
    readonly property var action: root._actions[root._kind] ?? null
    property bool _armed: false
    property real _lastTick: 0

    readonly property var _actions: ({
        logout:   { label: "Log out",   glyph: "󰍃", phrase: "Logging out",  failTitle: "Log out failed" },
        reboot:   { label: "Reboot",    glyph: "󰑐", phrase: "Rebooting",    failTitle: "Reboot failed" },
        poweroff: { label: "Power off", glyph: "󰐥", phrase: "Powering off", failTitle: "Shut down failed" }
    })

    signal started()

    function _command(kind: string): var {
        if (kind === "logout") return Settings.logoutCommand
        if (kind === "reboot") return Settings.rebootCommand
        if (kind === "poweroff") return Settings.poweroffCommand
        return []
    }

    function request(kind: string, screen: ShellScreen): void {
        if (!root._actions[kind]) return
        root._kind = kind
        root._remaining = root.seconds
        root._deadline = Date.now() + root.seconds * 1000
        root._lastTick = Date.now()
        root.triggerScreen = screen
        root._armed = true
        root.open = true
        // the coordinator refuses opens while idle or in overview
        if (!root.open) { root.close(); return }
        root.started()
    }

    function confirm(): void {
        if (!root.open || !root._armed || !root.action) return
        const command = root._command(root._kind)
        const title = root.action.failTitle
        root.close()
        root.run(command, title)
    }

    function run(command, failTitle: string): void {
        // a test copy must never lock, suspend or end the real session
        if (Quickshell.env("SILERE_SANDBOX") === "1") {
            console.info("silere-shell: sandboxed power action skipped:", command.join(" "))
            return
        }
        SystemTools.runOrNotify(command, failTitle)
    }

    Connections {
        target: root
        function onOpenChanged() { if (!root.open) root._armed = false }
    }

    // the deadline is the one clock: the card's bar drains toward it too, so the seconds,
    // the bar and the action can't drift apart the way counted ticks would
    Timer {
        interval: 250
        repeat: true
        running: root.open && root._armed
        onTriggered: {
            const now = Date.now()
            const late = now - root._lastTick
            root._lastTick = now
            // a tick this late means the machine slept through the countdown; nobody was
            // there to cancel it, so it must not fire on wake
            if (late > 2000) { root.close(); return }
            const left = root._deadline - now
            if (left <= 0) { root.confirm(); return }
            root._remaining = Math.ceil(left / 1000)
        }
    }
}
