pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // one list, so a row reused in another panel does not leave its service keyed to the first
    readonly property bool anyOpen: {
        const list = OverlayCoordinator.popups
        for (let i = 0; i < list.length; i++) {
            if (list[i].controlSurface && list[i].open) return true
        }
        return false
    }
    readonly property bool anyAnchoredOpen: {
        const list = OverlayCoordinator.popups
        for (let i = 0; i < list.length; i++) {
            if (list[i].blocksBarHints && list[i].open) return true
        }
        return false
    }

    signal opened()

    Connections {
        target: OverlayCoordinator
        function onPopupOpenedState(state) {
            if (state.controlSurface) root.opened()
        }
    }
}
