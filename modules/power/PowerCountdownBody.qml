import QtQuick
import "../../config"
import "../common"

// What a power countdown card shows, with no idea who counts. The desktop card and the lock
// screen each drive their own countdown, so this takes plain text and a 0..1 fill and only
// reports the two buttons.
Column {
    id: root

    property string glyph: ""
    property string title: ""
    property string message: ""
    property real progress: 1.0
    property string confirmLabel: ""

    signal cancelled()
    signal confirmed()

    spacing: 10

    Row {
        spacing: 9

        ShellText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            color: Theme.accent
            font.pixelSize: Settings.fontSize
        }
        ShellText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            color: Theme.text
            font.pixelSize: Settings.fontSize
            font.weight: Font.DemiBold
        }
    }

    ShellText {
        width: parent.width
        text: root.message
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
            width: _track.width * root.progress
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
                onTriggered: root.cancelled()
            }
            ActionButton {
                label: root.confirmLabel
                emphasis: true
                onTriggered: root.confirmed()
            }
        }
    }
}
