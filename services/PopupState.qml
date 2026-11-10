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

    // a centered picker has no anchor to place, so its keybind opens it as it stands
    function toggle(): void {
        if (root.open) { root.close(); return }
        root.open = true
    }

    // the coordinator refuses an open while the session is idle or the overview is up;
    // IPC callers and probes may match this text, so its wording stays fixed
    function refusedOpenText(noun: string, verb: string): string {
        return "error: " + noun + " " + verb
            + " closed while the session is idle or the overview is open"
    }
}
