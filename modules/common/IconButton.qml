pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

ButtonBase {
    id: root

    property int buttonSize: Metrics.rowHeightFor(28)
    property int glyphPixelSize: Settings.fontSize + 2

    implicitWidth: buttonSize
    implicitHeight: buttonSize

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        antialiasing: true
        scale: root.pressed ? Motion.pressScale
            : root.hovered ? Motion.hoverScale : 1.0
        transformOrigin: Item.Center
        // bare at rest, unlike the shared buttonFill treatment: these sit in
        // compact rows (calendar header) where three resting rings read as clutter
        color: root.hovered || root.pressed
            ? Theme.buttonFill(root.accentColor, root.hovered, root.pressed)
            : "transparent"

        OutlineBorder {
            radius: width / 2
            outlineWidth: 1
            outlineColor: root.hovered || root.pressed
                ? Theme.buttonLine(root.accentColor, root.hovered, root.pressed)
                : "transparent"
            ColorFade on outlineColor {}
        }

        ColorFade on color {}
        MotionBehavior on scale {
            id: _scaleMotion
            NumberAnimation {
                duration: _scaleMotion.targetValue < 1 ? Motion.press
                    : _scaleMotion.targetValue > 1 ? Motion.hoverIn : Motion.hoverOut
                easing.type: Easing.OutCubic
            }
        }
    }

    ShellText {
        anchors.centerIn: parent
        text: root.glyph
        color: root.hovered || root.pressed
            ? Theme.text : Theme.withAlpha(Theme.subtext, 0.72)
        font.pixelSize: root.glyphPixelSize

        ColorFade on color {}
    }
}
