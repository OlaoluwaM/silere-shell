import QtQuick
import "../../config"
import "../common"

// The lock's one action, in the corner opposite the field and the same height, so the
// bottom edge reads as one line. It opens the power card and does nothing else.
ButtonBase {
    id: root

    glyph: "󰐥"
    accessibleName: "Power"

    implicitWidth: Metrics.rowHeightFor(48)
    implicitHeight: Metrics.rowHeightFor(48)

    // the field's ground, so the two read as a pair over the wallpaper; the shared button
    // wash lies over it, since alone it is too faint to hold up against a bright wallpaper
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusControl
        antialiasing: true
        color: Theme.withAlpha(Theme.background, 0.55)

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            antialiasing: true
            color: Theme.buttonFill(root.accentColor, root.hovered, root.pressed)
            ColorFade on color {}
        }

        OutlineBorder {
            radius: parent.radius
            outlineColor: Theme.buttonLine(root.accentColor, root.hovered, root.pressed)
            ColorFade on outlineColor {}
        }
    }

    ShellText {
        anchors.centerIn: parent
        text: root.glyph
        color: root.hovered || root.pressed ? Theme.text : Theme.withAlpha(Theme.text, 0.82)
        font.pixelSize: LockState.px(17)
        ColorFade on color {}
    }
}
