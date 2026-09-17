pragma Singleton

import QtQuick

// State for MediaPopupWindow (modules/mediapopup), the anchored MediaCard popup the
// bar's media widget opens on left-click -- GNOME media-controller style, a small
// panel hung off the bar tile instead of a full menu open.
AnchoredPopupState {
    id: root

    anchorRecoveryMs: 0
    // the widget's own slot fades rather than unloading when playback stops, so
    // anchorSource never nulls on its own -- watch Media directly, same reasoning
    // TrayPopupState watches SystemTray.items instead of trusting the pill's visibility
    Connections {
        target: Media
        function onShownChanged() { if (root.open && !Media.shown) root.close() }
    }

    function toggleAt(x: real, screen, source): void {
        if (open) { close(); return }
        openAt(x, screen, source)
    }
}
