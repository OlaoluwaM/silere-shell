pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // one list, so a row reused in another panel does not leave its service keyed to the first
    readonly property bool anyOpen: MenuState.open || QuickActionsState.open
    readonly property bool anyAnchoredOpen: anyOpen
        || CalendarState.open || TrayMenuState.open

}
