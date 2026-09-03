pragma Singleton

import QtQuick
import Quickshell
import "../config"

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

    // a widget that resizes under the pointer re-requests with a fresh anchor; restarting the
    // dwell there holds the hint back for as long as it moves. Arguments, not live state, so it is testable
    function _dwellSurvives(sameOwner: bool, sameText: bool, dwelling: bool): bool {
        return sameOwner && sameText && dwelling
    }

    // how long the pointer rests before a hint shows. A widget whose click opens a surface
    // may ask for longer, so a deliberate click lands before the hint and never under it
    readonly property int showDelay: 520
    property int _pendingDelay: 0

    function request(owner, screen, x: real, label: string, delay): void {
        const next = String(label || "").trim()
        if (!owner || !screen || !isFinite(x) || next.length === 0 || root._blocked()) {
            root.release(owner)
            return
        }

        const settling = root._dwellSurvives(root._owner === owner,
            root._pendingText === next, _showDelay.running)
        _closeDelay.stop()
        root._owner = owner
        root._pendingScreen = screen
        root._pendingAnchorX = x
        root._pendingText = next
        root._pendingDelay = Number(delay) > 0 ? Number(delay) : 0
        if (root.open) root._showPending()
        else if (!settling) _showDelay.restart()
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
        _exitSettle.stop()
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
            // the screen goes at once: the popup loader latches its own copy for the exit
            root.triggerScreen = null
            _exitSettle.restart()
        }
    }

    // the popup's width follows its text and its place follows the anchor, so clearing them
    // at close collapses and shifts the box while the exit is still fading; they hold until it has run
    Timer {
        id: _exitSettle
        interval: Math.max(Motion.popOut, Motion.popOutFade)
        onTriggered: {
            if (root.open) return
            root.anchorX = 0
            root.text = ""
        }
    }

    Timer {
        id: _showDelay
        interval: root._pendingDelay > 0 ? root._pendingDelay : root.showDelay
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
