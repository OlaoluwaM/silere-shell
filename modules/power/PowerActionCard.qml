pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../common"

// The power rail's countdown before Log out, Reboot or Power off. Centered like the
// keybinds card: Escape, a tap outside or Cancel all cancel, and since nothing has run
// yet there is nothing to undo.
OverlayPopupWindow {
    id: win

    required property ShellScreen targetScreen

    screen: targetScreen
    // leaving the workspace is a way out like any other: closing this state on a switch
    // cancels, as it closes the other centered cards
    popupState: PowerActionState
    layerNamespace: "silere-power"
    popupCard: card

    Shortcut {
        sequences: ["Return", "Enter"]
        context: Qt.ApplicationShortcut
        enabled: PowerActionState.open
        onActivated: PowerActionState.confirm()
    }

    FloatingPopupCard {
        id: card

        win: win
        open: PowerActionState.open
        anchorX: win.width / 2
        barBottom: Metrics.barAtBottom
        centered: true
        animatePlacement: false

        readonly property int pad: 16
        readonly property var action: PowerActionState.action
        property real progress: 1.0

        width:  Math.round(Math.max(260, Math.min(340, win.width - 96)))
        height: Math.round(_body.implicitHeight + card.pad * 2)
        radius: Theme.radiusPanel

        // a fixed name: binding it to the ticking message would re-announce every second
        Accessible.role: Accessible.AlertMessage
        Accessible.name: card.action ? card.action.label : ""
        Accessible.description: _body.message

        // the duration is the countdown itself, which Motion must not scale or the bar would lie
        NumberAnimation {
            id: _drain
            target: card
            property: "progress"
            to: 0.0
            easing.type: Easing.Linear
        }

        function _startDrain(): void {
            _drain.stop()
            const total = PowerActionState.seconds * 1000
            const left = Math.max(0, Math.min(total, PowerActionState.deadline - Date.now()))
            card.progress = left / total
            if (ShellSettings.reduceMotion || left <= 0) return
            _drain.from = card.progress
            _drain.duration = left
            _drain.start()
        }

        Component.onCompleted: if (PowerActionState.open) card._startDrain()

        Connections {
            target: PowerActionState
            function onStarted() { card._startDrain() }
            // the bar holds where it stopped through the exit fade
            function onOpenChanged() { if (!PowerActionState.open) _drain.stop() }
            // without the drain the bar steps with the seconds instead
            function onRemainingChanged() {
                if (ShellSettings.reduceMotion)
                    card.progress = PowerActionState.remaining / PowerActionState.seconds
            }
        }

        PowerCountdownBody {
            id: _body
            x: card.pad
            y: card.pad
            width: card.width - card.pad * 2
            glyph: card.action ? card.action.glyph : ""
            title: card.action ? card.action.label : ""
            message: card.action
                ? card.action.phrase + " in " + PowerActionState.remaining
                    + (PowerActionState.remaining === 1 ? " second." : " seconds.")
                : ""
            progress: card.progress
            confirmLabel: card.action ? card.action.label : ""
            onCancelled: PowerActionState.close()
            onConfirmed: PowerActionState.confirm()
        }
    }
}
