pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool armed: true

    function _environmentBlocksControls(idle: bool, overview: bool): bool {
        return idle || overview
    }

    function closeAll(): void { root._claim("") }

    function _opened(name: string): void {
        // IPC and keybind requests can arrive after the environment edge that closed the surfaces, so reject re-entry until it becomes interactive
        if (root._environmentBlocksControls(Idle.isIdle, OverviewState.active)) {
            root.closeAll()
            return
        }
        root._claim(name)
    }

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
        function onOpenChanged() { if (MenuState.open) root._opened("menu") }
    }
    Connections {
        target: CalendarState
        function onOpenChanged() { if (CalendarState.open) root._opened("calendar") }
    }
    Connections {
        target: TrayMenuState
        function onOpenChanged() { if (TrayMenuState.open) root._opened("tray") }
    }
    Connections {
        target: TrayPopupState
        function onOpenChanged() { if (TrayPopupState.open) root._claim("traypopup") }
    }
    Connections {
        target: QuickActionsState
        function onOpenChanged() { if (QuickActionsState.open) root._opened("quickActions") }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (root._environmentBlocksControls(Idle.isIdle, OverviewState.active))
                root.closeAll()
        }
    }
    Connections {
        target: OverviewState
        function onActiveChanged() {
            if (root._environmentBlocksControls(Idle.isIdle, OverviewState.active))
                root.closeAll()
        }
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
