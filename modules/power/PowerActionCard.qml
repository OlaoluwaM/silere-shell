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
        Accessible.description: _message.text

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

        Column {
            id: _body
            x: card.pad
            y: card.pad
            width: card.width - card.pad * 2
            spacing: 10

            Row {
                spacing: 9

                ShellText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.action ? card.action.glyph : ""
                    color: Theme.accent
                    font.pixelSize: Settings.fontSize
                }
                ShellText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.action ? card.action.label : ""
                    color: Theme.text
                    font.pixelSize: Settings.fontSize
                    font.weight: Font.DemiBold
                }
            }

            ShellText {
                id: _message
                width: parent.width
                text: card.action
                    ? card.action.phrase + " in " + PowerActionState.remaining
                        + (PowerActionState.remaining === 1 ? " second." : " seconds.")
                    : ""
                wrapMode: Text.Wrap
                color: Theme.withAlpha(Theme.subtext, 0.86)
                font.pixelSize: Settings.fontLabel
            }

            Rectangle {
                id: _track
                width: parent.width
                height: 3
                radius: 1.5
                antialiasing: true
                color: Theme.controlFill(Theme.text, 0.06)

                Rectangle {
                    width: _track.width * card.progress
                    height: parent.height
                    radius: parent.radius
                    antialiasing: true
                    color: Theme.accent
                }
            }

            Item {
                width: parent.width
                height: _buttons.height + 4

                Row {
                    id: _buttons
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: 6

                    ActionButton {
                        label: "Cancel"
                        onTriggered: PowerActionState.close()
                    }
                    ActionButton {
                        label: card.action ? card.action.label : ""
                        emphasis: true
                        onTriggered: PowerActionState.confirm()
                    }
                }
            }
        }
    }
}
