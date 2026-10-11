pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Item {
    id: root

    property string glyph: ""
    property string accessibleName: ""
    property color accentColor: Theme.accent
    property int buttonSize: Metrics.rowHeightFor(28)
    property int glyphPixelSize: Settings.fontSize + 2

    signal triggered()

    readonly property bool pressed: _tap.pressed
    readonly property bool _canActivate: root.enabled && root.visible

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    width: implicitWidth
    height: implicitHeight
    opacity: enabled ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }

    function activate(): void {
        if (root._canActivate) root.triggered()
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.focusable: root._canActivate
    Accessible.onPressAction: root.activate()

    HoverHandler {
        id: _hover
        enabled: root._canActivate
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        id: _tap
        enabled: root._canActivate
        onTapped: {
            root.activate()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        antialiasing: true
        scale: root.pressed ? Motion.pressScale
            : _hover.hovered ? Motion.hoverScale : 1.0
        transformOrigin: Item.Center
        // bare at rest, unlike the shared buttonFill treatment: these sit in
        // compact rows (calendar header) where three resting rings read as clutter
        color: _hover.hovered || root.pressed
            ? Theme.buttonFill(root.accentColor, _hover.hovered, root.pressed)
            : "transparent"

        OutlineBorder {
            radius: width / 2
            outlineWidth: 1
            outlineColor: _hover.hovered || root.pressed
                ? Theme.buttonLine(root.accentColor, _hover.hovered, root.pressed)
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
        color: _hover.hovered || root.pressed
            ? Theme.text : Theme.withAlpha(Theme.subtext, 0.72)
        font.pixelSize: root.glyphPixelSize

        ColorFade on color {}
    }
}
