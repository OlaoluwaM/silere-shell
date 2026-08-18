pragma Singleton

import QtQuick
import Quickshell

// State for MediaPopupWindow (modules/mediapopup), the anchored MediaCard popup the
// bar's media widget opens on left-click -- GNOME media-controller style, a small
// panel hung off the bar tile instead of a full menu open. Mirrors TrayPopupState's
// open/anchor shape (services/TrayPopupState.qml) since both are single-window
// popups toggled from one bar tile, not a list of menu-owned surfaces.
Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property QtObject anchorSource: null
    property ShellScreen triggerScreen: null
    readonly property real effectiveAnchorX: {
        const live = Number(root.anchorSource?.menuAnchorX)
        return isFinite(live) ? live : root.anchorX
    }
    // follows the widget down if its BarZone slot is ever actually torn down
    // (media widget disabled in settings, bar recreated on a screen/position change)
    onAnchorSourceChanged: if (open && anchorSource === null) close()
    // the widget's own slot fades rather than unloading when playback stops, so
    // anchorSource never nulls on its own -- watch Media directly, same reasoning
    // TrayPopupState watches SystemTray.items instead of trusting the pill's visibility
    Connections {
        target: Media
        function onShownChanged() { if (root.open && !Media.shown) root.close() }
    }

    function toggleAt(x: real, screen, source): void {
        if (open) { close(); return }
        anchorX = x
        anchorSource = source ?? null
        triggerScreen = screen ?? null
        open = true
    }
    function close(): void {
        if (open) open = false
        anchorSource = null
        triggerScreen = null
    }
}
