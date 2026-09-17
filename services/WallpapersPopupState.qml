pragma Singleton

import QtQuick

// State for WallpapersPopup (modules/wallpapers). No anchor/anchorSource here unlike
// TrayPopupState/QuickActionsState: this popup is a centered overlay, not placed off a
// bar pill, so there is no source widget to track or fall back from -- the trigger is
// always the IPC toggle (Wallpapers.qml), which has no screen of its own to hand in either,
// so triggerScreen stays null and shell.qml's PopupLoader falls back to activeOverlayScreen.
PopupState {
    id: root

    // QML singletons instantiate lazily, on first reference. shell.qml references this
    // singleton eagerly (the PopupLoader's wantOpen binding), but nothing eager referenced
    // Wallpapers itself -- its popup surface only exists after open flips, and the IPC
    // handler that flips it lives in Wallpapers. Net effect: the "wallpapers" IPC target
    // would never register and the toggle chord would be a no-op. This binding is the
    // bootstrap: it drags Wallpapers (and its IpcHandler) into existence at shell start.
    readonly property bool available: Wallpapers.available

    function toggle(): void {
        if (open) { close(); return }
        open = true
    }
}
