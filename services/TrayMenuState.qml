pragma Singleton

import QtQuick

AnchoredPopupState {
    id: root

    property QtObject sourceItem: null
    property bool barBottom: false
    // QtObject (not var) so the reference auto-nulls when the SNI item dies with the menu open
    property QtObject menuHandle: null
    // true when this menu was opened from a row inside TrayPopupWindow rather than the
    // inline bar row (TrayWidget.qml) -- OverlayCoordinator reads this to know the popup
    // is this menu's parent, not a sibling overlay, so opening one must not kill the other
    property bool popupSourced: false

    onMenuHandleChanged: if (open && menuHandle === null) close()
    // every close path lands here, so the menu-specific handles clear without overriding close()
    onOpenChanged: if (!open) {
        sourceItem = null
        menuHandle = null
        popupSourced = false
    }

    Connections {
        target: ShellSettings
        function onTrayWidgetChanged() { if (!ShellSettings.trayWidget) root.close() }
    }

    function toggleAt(x: real, screen, handle, bottom: bool, anchor, source, fromPopup): void {
        if (root.open && root.sourceItem === source) {
            root.close()
            return
        }
        sourceItem = source ?? null
        barBottom = bottom
        menuHandle = handle
        popupSourced = fromPopup === true
        openAt(x, screen, anchor)
    }
}
