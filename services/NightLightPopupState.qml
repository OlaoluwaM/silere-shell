pragma Singleton

import QtQuick
import Quickshell.Io

// State for NightLightPopup (modules/nightlight), the card the menu's Night Light row
// opens in the menu's place. A control surface, so NightLight reads sunsetr's config and
// state afresh whenever the card opens, as it does for the menu.
AnchoredPopupState {
    id: root

    controlSurface: true

    IpcHandler {
        target: "nightlight"

        function toggle(): string {
            if (root.open) { root.close(); return "ok" }
            // no widget to anchor to: borrow the spot the menu would open at
            root.anchorX = MenuState.anchorX
            root.openUnanchored()
            return root.open ? "ok" : root.refusedOpenText("the night light card", "stays")
        }
        function close(): void { root.close() }
    }
}
