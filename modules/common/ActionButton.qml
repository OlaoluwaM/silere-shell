import QtQuick
import "../../config"

ButtonBase {
    id: root

    property string label: ""
    property bool emphasis: false
    property real radius: Theme.radiusField
    // the label's face; the glyph keeps the shell's font, which carries the icons
    property string fontFamily: Settings.font

    accessibleName: label

    // ceil: a fractional width lands the outline stroke off-pixel under fractional scaling
    implicitWidth: Math.ceil(_row.implicitWidth) + 20
    implicitHeight: Metrics.rowHeightFor(32)

    // no scale anywhere: scaling text resamples every glyph for as long as it lasts. Hover
    // doesn't lift the surface either: at a fractional output scale a logical pixel lands
    // between device pixels, so an animated lift resamples the label the same way, and the
    // fill already marks hover. Only a press nudges the surface, for as long as it's held
    Rectangle {
        id: _surface
        anchors.left: parent.left
        anchors.right: parent.right
        y: root.pressed ? 1 : 0
        height: parent.height - y
        MotionBehavior on y {
            id: _pressMotion
            NumberAnimation {
                duration: _pressMotion.targetValue > 0 ? Motion.press : Motion.hoverOut
                easing.type: Easing.OutCubic
            }
        }
        radius: root.radius
        antialiasing: true
        color: root.emphasis
            ? Theme.emphasisButtonFill(root.accentColor, root.hovered, root.pressed)
            : Theme.buttonFill(root.accentColor, root.hovered, root.pressed)

        ColorFade on color {}

        OutlineBorder {
            radius: _surface.radius
            outlineWidth: 1
            outlineColor: root.emphasis ? "transparent"
                    : Theme.buttonLine(root.accentColor, root.hovered, root.pressed)

            ColorFade on outlineColor {}
        }

        Row {
            id: _row
            anchors.centerIn: parent
            spacing: root.glyph.length > 0 && root.label.length > 0 ? 7 : 0
            ShellText {
                visible: root.glyph.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyph
                color: root.emphasis
                    ? Theme.mix(Theme.text, root.accentColor, 0.10)
                    : root.hovered
                        ? Theme.mix(Theme.subtext, root.accentColor, 0.22)
                        : Theme.withAlpha(Theme.subtext, 0.82)
                font.pixelSize: Settings.fontSize
                ColorFade on color {}
            }
            ShellText {
                visible: root.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.label
                font.family: root.fontFamily
                color: root.emphasis ? Theme.text
                    : root.hovered
                        ? Theme.mix(Theme.text, root.accentColor, 0.07)
                        : Theme.withAlpha(Theme.text, 0.80)
                font.pixelSize: Settings.fontLabel
                font.weight: root.emphasis ? Font.DemiBold : Font.Normal
                ColorFade on color {}
            }
        }
    }
}
