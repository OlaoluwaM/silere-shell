pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"
import "../menu/controls"

// GNOME media-controller style: left-clicking the bar's media widget hangs this small
// panel off the tile instead of opening the full menu. Structure mirrors
// modules/traypopup/TrayPopupWindow.qml (own layer surface, FloatingPopupCard chrome,
// OutsideTapGuard/Escape dismissal) since both are single-window popups toggled from
// one bar tile -- the only real difference is the payload, MediaCard instead of a row list.
PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property string _output: Compositor.monitorName(win.screen)

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && MediaPopupState.open) MediaPopupState.close()
        }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-mediapopup"
    WlrLayershell.keyboardFocus: MediaPopupState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: MediaPopupState.open || card.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: MediaPopupState.open; onActivated: MediaPopupState.close() }

    OutsideTapGuard {
        id: _tapGuard
        open: MediaPopupState.open
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: MediaPopupState.open ? _fillArea : null }

    TapHandler {
        id: _dismiss
        enabled: MediaPopupState.open && card.scaleAmt > 0.95
        onTapped: {
            if (_tapGuard.ignoring) return
            const p = _dismiss.point.position
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                MediaPopupState.close()
        }
    }

    PopupShadow { card: card }

    FloatingPopupCard {
        id: card
        win: win
        open: MediaPopupState.open
        anchorX: MediaPopupState.effectiveAnchorX
        barBottom: Metrics.barAtBottom

        // matches HomePage's home-tab content width (menu compactW 398 minus the
        // collapsed rail and its padding) so the card reads at the same scale it
        // does inside the menu, not stretched or cramped for this smaller surface
        readonly property int cardWidth: 330

        // edge to edge: the media card IS this popup's surface. An inset frame around
        // it just showed a ring of empty popup chrome behind the art, so the card
        // fills the window card completely and adopts its corner radius below.
        width:  cardWidth
        height: _mediaCard.height

        Connections {
            target: MediaPopupState
            function onOpenChanged() { if (MediaPopupState.open) card.forceActiveFocus() }
        }
        Component.onCompleted: if (MediaPopupState.open) card.forceActiveFocus()

        MediaCard {
            id: _mediaCard
            width: card.cardWidth
            // the outer card clips at Theme.surfaceRadius; matching it keeps the art's
            // corners exactly on the popup's own rounding instead of double-rounding
            radius: card.radius
            // MediaCard's art-retry-on-reopen defaults to watching MenuState (its original,
            // only host); this popup is a second host, so it tells the card which singleton
            // actually governs its own visibility instead of leaving it watching MenuState,
            // which never opens here
            hostOpen: MediaPopupState.open
        }
    }
}
