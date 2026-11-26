pragma Singleton

import QtQuick
import Quickshell.Io

// State for NightLightPopup (modules/nightlight), the card the menu's Night Light row
// opens in the menu's place. A control surface, so NightLight reads sunsetr's config and
// state afresh whenever the card opens, as it does for the menu.
AnchoredPopupState {
    id: root

    controlSurface: true

    // true while the card stands where the menu just was, so its entrance waits for the menu to leave
    property bool fromMenu: false
    onOpenChanged: if (!open) fromMenu = false

    // the menu's Night Light row opens the card at the menu's own anchor; the coordinator closes
    // the menu as the card opens, and the card enters once the menu has left
    function openFromMenu(): void {
        MenuState.handingOver = true
        root.fromMenu = true
        root.openAt(MenuState.effectiveAnchorX, MenuState.triggerScreen, MenuState.anchorSource)
        // the coordinator turns an open away while the shell is idle or the overview is up,
        // and neither side keeps a mark for a swap that never happened
        if (!root.open) {
            MenuState.handingOver = false
            root.fromMenu = false
        }
    }

    IpcHandler {
        target: "nightlight"

        function toggle(): string {
            if (root.open) { root.close(); return "ok" }
            // with the menu up the card takes its place, as it does from the menu's own row
            if (MenuState.open) root.openFromMenu()
            else {
                // no widget to anchor to: borrow the spot the menu would open at
                root.anchorX = MenuState.anchorX
                root.openUnanchored()
            }
            return root.open ? "ok" : root.refusedOpenText("the night light card", "stays")
        }
        function close(): void { root.close() }
    }
}
