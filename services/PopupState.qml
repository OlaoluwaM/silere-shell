import QtQuick
import Quickshell

Singleton {
    id: root

    property bool open: false
    property ShellScreen triggerScreen: null
    property bool controlSurface: false
    property bool blocksBarHints: false
    property QtObject popupParent: null

    Component.onCompleted: OverlayCoordinator.registerPopup(root)

    // A child preserves unregistering when a derived state has its own destruction
    // handler, such as CalendarState's persistence flush.
    QtObject {
        Component.onDestruction: OverlayCoordinator.unregisterPopup(root)
    }

    // A Connections object keeps derived cleanup handlers from replacing lifecycle registration.
    Connections {
        target: root
        function onOpenChanged() {
            if (root.open) OverlayCoordinator.popupOpened(root)
            else OverlayCoordinator.popupClosed(root)
        }
    }

    function close(): void {
        if (root.open) root.open = false
        root.triggerScreen = null
    }
}
