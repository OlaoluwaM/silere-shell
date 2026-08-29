pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    property bool open: false
    property ShellScreen triggerScreen: null
    property real anchorX: 0
    property string text: ""

    property var _owner: null
    property ShellScreen _pendingScreen: null
    property real _pendingAnchorX: 0
    property string _pendingText: ""

    function _blocked(): bool {
        return !ShellSettings.barTooltips || Idle.isIdle || OverviewState.active
            || ControlSurfaces.anyAnchoredOpen
    }

    function request(owner, screen, x: real, label: string): void {
        const next = String(label || "").trim()
        if (!owner || !screen || !isFinite(x) || next.length === 0 || root._blocked()) {
            root.release(owner)
            return
        }

        _closeDelay.stop()
        root._owner = owner
        root._pendingScreen = screen
        root._pendingAnchorX = x
        root._pendingText = next
        if (root.open) root._showPending()
        else _showDelay.restart()
    }

    function release(owner): void {
        if (root._owner !== owner) return
        _showDelay.stop()
        if (root.open) _closeDelay.restart()
        else root._clear()
    }

    function close(): void {
        _showDelay.stop()
        _closeDelay.stop()
        root.open = false
        root._clear()
    }

    function _showPending(): void {
        if (!root._owner || !root._pendingScreen || root._pendingText.length === 0
                || root._blocked()) {
            root.close()
            return
        }
        root.triggerScreen = root._pendingScreen
        root.anchorX = root._pendingAnchorX
        root.text = root._pendingText
        root.open = true
    }

    function _clear(): void {
        root._owner = null
        root._pendingScreen = null
        root._pendingAnchorX = 0
        root._pendingText = ""
        if (!root.open) {
            root.triggerScreen = null
            root.anchorX = 0
            root.text = ""
        }
    }

    Timer {
        id: _showDelay
        interval: 520
        onTriggered: root._showPending()
    }

    Timer {
        id: _closeDelay
        interval: 70
        onTriggered: root.close()
    }

    Connections {
        target: ShellSettings
        function onBarTooltipsChanged() {
            if (!ShellSettings.barTooltips) root.close()
        }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() { if (Idle.isIdle) root.close() }
    }
    Connections {
        target: OverviewState
        function onActiveChanged() { if (OverviewState.active) root.close() }
    }
    Connections {
        target: ControlSurfaces
        function onAnyAnchoredOpenChanged() {
            if (ControlSurfaces.anyAnchoredOpen) root.close()
        }
    }
}
