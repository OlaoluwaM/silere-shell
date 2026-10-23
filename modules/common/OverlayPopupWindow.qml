pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../services"

// A full-screen overlay surface that hosts one FloatingPopupCard. The surface stays
// full screen only to catch the closing tap; the card places itself inside it.
//
// Each popup declares its own required targetScreen and sets screen from it: that
// declaration is how the panel probe finds a layer-shell surface, and a base declaring
// it would hide every popup from the probe and list itself instead.
PanelWindow {
    id: root

    required property PopupState popupState
    required property string layerNamespace
    required property FloatingPopupCard popupCard

    readonly property string _output: Compositor.monitorName(root.screen)

    // overridden by a popup whose Escape first backs out of something inside the card
    function handleEscape(): void {
        root.popupState.close()
    }

    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: root.layerNamespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.popupState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // the card's opacity holds the surface up until its exit fade ends
    visible: root.popupState.open || root.popupCard.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    // On Hyprland this signal also fires for monitor focus (focusedmon, activemon), so with
    // several outputs, moving the pointer to another monitor and back closes too. It fails
    // safe, and splitting real workspace switches out would mean a new signal on the shared
    // Compositor boundary.
    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === root._output && root.popupState.open) root.popupState.close()
        }
    }

    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: root.popupState.open
        onActivated: root.handleEscape()
    }

    OutsideTapGuard {
        id: _tapGuard
        open: root.popupState.open
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: root.popupState.open ? _fillArea : null }

    TapHandler {
        id: _dismiss
        enabled: root.popupState.open
        onTapped: {
            if (_tapGuard.ignoring) return
            const p = _dismiss.point.position
            const c = root.popupCard
            if (p.x < c.x || p.x > c.x + c.width ||
                p.y < c.y || p.y > c.y + c.height)
                root.popupState.close()
        }
    }

    PopupShadow { card: root.popupCard }
}
