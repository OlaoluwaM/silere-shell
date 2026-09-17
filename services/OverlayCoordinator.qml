pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool armed: true
    readonly property var popups: root._popups
    property var _popups: []
    property var _openPopups: []
    readonly property int _openCount: root._openPopups.length
    readonly property bool anyOpen: root._openCount > 0

    signal popupOpenedState(var state)

    function _environmentBlocksControls(idle: bool, overview: bool): bool {
        return idle || overview
    }

    function _registerPopup(state): bool {
        if (!state || root._popups.indexOf(state) >= 0) return false
        root._popups = root._popups.concat([state])
        return true
    }

    function registerPopup(state): void {
        if (!state) return
        root._registerPopup(state)
        if (state.open) root.popupOpened(state)
    }

    function unregisterPopup(state): void {
        const index = root._popups.indexOf(state)
        if (index >= 0) {
            const list = root._popups.slice()
            list.splice(index, 1)
            root._popups = list
        }
        root.popupClosed(state)
    }

    function popupOpened(state): void {
        if (!state) return
        root._registerPopup(state)
        if (root._openPopups.indexOf(state) >= 0) return
        root._openPopups = root._openPopups.concat([state])
        // IPC and keybind requests can arrive after the environment edge that closed the surfaces, so reject re-entry until it becomes interactive
        if (root._environmentBlocksControls(Idle.isIdle, OverviewState.active)) {
            root.closeAll()
            return
        }
        root._closeOthers(state)
        if (state.open) root.popupOpenedState(state)
    }

    function popupClosed(state): void {
        const index = root._openPopups.indexOf(state)
        if (index < 0) return
        const list = root._openPopups.slice()
        list.splice(index, 1)
        root._openPopups = list
    }

    function closeAll(): void {
        // close() re-enters popupClosed, so iterate a copy that cannot shift underneath
        const list = root._popups.slice()
        for (let i = 0; i < list.length; i++) list[i].close()
    }

    function _closeOthers(opener): void {
        const list = root._popups.slice()
        for (let i = 0; i < list.length; i++) {
            if (list[i] !== opener && opener.popupParent !== list[i]) list[i].close()
        }
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
}
