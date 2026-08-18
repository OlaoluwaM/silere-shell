pragma Singleton

import QtQuick
import Quickshell

// State for KeybindsPopup (modules/keybinds). No anchor/anchorSource here unlike
// TrayPopupState/QuickActionsState: this popup is a centered overlay, not placed off a
// bar pill, so there is no source widget to track or fall back from -- the trigger is
// always the IPC toggle (Keybinds.qml), which has no screen of its own to hand in either,
// so triggerScreen stays null and shell.qml's PopupLoader falls back to activeOverlayScreen.
Singleton {
    id: root

    property bool open: false
    property ShellScreen triggerScreen: null

    function toggle(): void {
        if (open) { close(); return }
        triggerScreen = null
        open = true
    }
    function close(): void {
        if (open) open = false
        triggerScreen = null
    }
}
