pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool armed: true

    // "tray" (the item context menu, TrayMenuState) is only a child of "traypopup"
    // (the tray list, TrayPopupState) when TrayMenuState.popupSourced says a popup row
    // opened it -- the same TrayMenuState also serves the inline bar row (TrayWidget.qml),
    // an unrelated overlay the popup must still close normally. Name-matching alone can't
    // tell those apart, since both call the same toggleAt().
    function _claim(name: string): void {
        const trayMenuIsPopupChild = TrayMenuState.open && TrayMenuState.popupSourced
        if (name !== "menu") MenuState.close()
        if (name !== "calendar") CalendarState.close()
        if (name !== "tray") TrayMenuState.close()
        if (name !== "traypopup" && !(name === "tray" && trayMenuIsPopupChild))
            TrayPopupState.close()
        if (name !== "quickActions") QuickActionsState.close()
        if (name !== "keybinds") KeybindsPopupState.close()
        if (name !== "wallpapers") WallpapersPopupState.close()
    }

    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root._claim("menu") }
    }
    Connections {
        target: CalendarState
        function onOpenChanged() { if (CalendarState.open) root._claim("calendar") }
    }
    Connections {
        target: TrayMenuState
        function onOpenChanged() { if (TrayMenuState.open) root._claim("tray") }
    }
    Connections {
        target: TrayPopupState
        function onOpenChanged() { if (TrayPopupState.open) root._claim("traypopup") }
    }
    Connections {
        target: QuickActionsState
        function onOpenChanged() { if (QuickActionsState.open) root._claim("quickActions") }
    }
    Connections {
        target: KeybindsPopupState
        function onOpenChanged() { if (KeybindsPopupState.open) root._claim("keybinds") }
    }
    Connections {
        target: WallpapersPopupState
        function onOpenChanged() { if (WallpapersPopupState.open) root._claim("wallpapers") }
    }
}
