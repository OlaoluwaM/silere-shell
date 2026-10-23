import QtQuick
import "../../config"

// the shared shell of ActionButton and IconButton: activation gating, hover/press state and
// the disabled fade. Each button only adds its own surface and content
Item {
    id: root

    property string glyph: ""
    property string accessibleName: ""
    property color accentColor: Theme.accent

    signal triggered()

    readonly property bool pressed: _tap.pressed
    readonly property bool hovered: _hover.hovered
    readonly property bool _canActivate: root.enabled && root.visible

    width: implicitWidth
    height: implicitHeight
    opacity: root.enabled ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.fast }
    }

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
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: _tap
        enabled: root._canActivate
        onTapped: {
            root.activate()
        }
    }
}
