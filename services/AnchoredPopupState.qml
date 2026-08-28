import QtQuick
import Quickshell

Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property QtObject anchorSource: null
    property ShellScreen triggerScreen: null

    readonly property real effectiveAnchorX: {
        const live = Number(root.anchorSource?.menuAnchorX)
        return isFinite(live) ? live : root.anchorX
    }

    // a destroyed widget nulls this with no assignment behind it. Reordering bar widgets
    // hands the zone's Repeater a new array, which rebuilds every delegate, so the anchor
    // drops for a turn and comes straight back; only a bar that really went never returns.
    property bool _anchorWriting: false
    function _setAnchor(source): void {
        _anchorRegrab.stop()
        root._anchorWriting = true
        root.anchorSource = source ?? null
        root._anchorWriting = false
    }
    // claimed by whichever live widget asks first, not by the one being rebuilt: a zone's
    // Repeater creates the replacements before it destroys the originals, and the
    // destruction is deferred, so an edge-triggered handover lands on a dying instance
    function adoptAnchor(source): void {
        if (!root.open || !source) return
        if (root._anchorWriting || root.anchorSource !== null) return
        root._setAnchor(source)
    }
    onAnchorSourceChanged: {
        if (anchorSource !== null) { _anchorRegrab.stop(); return }
        if (root._anchorWriting || !root.open) return
        _anchorRegrab.restart()
    }
    // never expose this timer's state: a consumer that reacts by taking the anchor stops the very timer it is bound to, which is a binding loop
    Timer {
        id: _anchorRegrab
        interval: 150
        onTriggered: if (root.open && root.anchorSource === null) root.close()
    }

    // keybind and IPC opens have no widget to anchor to; a live one adopts on the next turn
    function _unanchor(): void {
        root.triggerScreen = null
        root._setAnchor(null)
    }
    function openUnanchored(): void {
        root._unanchor()
        root.open = true
    }

    function openAt(x: real, screen, source): void {
        root.anchorX = x
        root._setAnchor(source)
        root.triggerScreen = screen ?? null
        root.open = true
    }
    function close(): void {
        // open first: clearing anchorSource while open re-enters close() through its handler
        if (root.open) root.open = false
        root.triggerScreen = null
        root._setAnchor(null)
    }

    // --- fork extension: shared keybind-open fallback-anchor targeting ----------
    // A keybind or IPC open has no trigger widget, so a state's fallback anchorX
    // has to come from whichever live widget sits on the overlay bar (services/
    // Monitors.qml), and highlighting an open popup on a bar needs to know whether
    // it's this state that's showing there. Every trigger widget used to re-derive
    // both independently per state; centralised here so a state answers for
    // itself and a widget only ever supplies its own screen and geometry.
    function targetsScreen(screen): bool {
        if (!screen) return false
        return root.triggerScreen ? root.triggerScreen.name === screen.name
                                   : Monitors.activeName === screen.name
    }
    // widgets call this unconditionally; only the one on the overlay bar actually writes
    function publishFallbackAnchor(screen, x: real): void {
        if (!screen || screen.name !== Monitors.overlayBarName) return
        root.anchorX = x
    }
}
