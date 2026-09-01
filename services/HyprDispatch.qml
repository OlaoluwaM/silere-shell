pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    // the lua config framework replaces the plain dispatchers, so this has to be
    // known here rather than set by a caller: whichever singleton dispatches
    // first may be the only one ever instantiated
    property bool useLua: false
    property bool _luaChecked: false

    BoundedProcess {
        id: _luaCheck
        timeoutMs: 10000
        command: ["bash", Quickshell.shellDir + "/scripts/install.sh", "--hypr-config-kind"]
        onExited: (code) => {
            if (!SystemTools.hasHyprctl) {
                root.useLua = false
                root._luaChecked = false
                return
            }
            root.useLua = (code === 0)
            root._luaChecked = true
        }
    }

    // hasHyprctl arrives asynchronously, so this is retried rather than read once
    function _detectLua(): void {
        if (root._luaChecked || _luaCheck.running) return
        if (!SystemTools.ready || !SystemTools.hasHyprctl) return
        _luaCheck.running = true
    }

    Component.onCompleted: root._detectLua()
    Connections {
        target: SystemTools
        function onReadyChanged() { root._detectLua() }
        function onScanRevisionChanged() {
            root._luaChecked = false
            root.useLua = false
            if (!SystemTools.hasHyprctl && _luaCheck.running) _luaCheck.running = false
            root._detectLua()
        }
    }

    function _quote(value): string {
        return "\"" + String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\""
    }

    function _value(value): string {
        const text = String(value)
        return /^-?\d+$/.test(text) ? text : root._quote(text)
    }

    function _luaCall(dispatcher, args): string {
        if (dispatcher === "focusmonitor")
            return "hl.dsp.focus({ monitor = " + root._quote(args) + " })"
        if (dispatcher === "workspace")
            return "hl.dsp.focus({ workspace = " + root._value(args) + " })"
        if (dispatcher === "movetoworkspacesilent")
            return "hl.dsp.window.move({ workspace = " + root._value(args) + ", follow = false })"
        if (dispatcher === "focuswindow")
            return "hl.dsp.focus({ window = " + root._quote(args) + " })"
        return ""
    }

    function _text(dispatcher, args): string {
        if (root.useLua) {
            const call = root._luaCall(dispatcher, args)
            if (call.length > 0) return call
        }
        return (args !== undefined && args !== null && String(args).length > 0)
            ? dispatcher + " " + String(args) : dispatcher
    }

    // Hyprland.dispatch(request) writes straight to the compositor's IPC socket
    // in-process, so there's no argv to assemble — _text() already builds the exact
    // same "dispatcher [args]" (or quoted lua-framework call) string a forked
    // `hyprctl dispatch <that text>` used to receive as its one request argument.
    function dispatch(dispatcher, args): void {
        if (!SystemTools.ready || !SystemTools.hasHyprctl) return
        Hyprland.dispatch(root._text(dispatcher, args))
    }

    // two sequential in-process dispatches instead of a forked sh + two hyprctls:
    // the socket serializes writes, so back-to-back calls land in the same order the
    // sh chain existed to guarantee, without needing a shell to sequence detached
    // processes or --batch, which mangled the quoted lua-framework calls
    function dispatchPair(d1, a1, d2, a2): void {
        if (!SystemTools.ready || !SystemTools.hasHyprctl) return
        Hyprland.dispatch(root._text(d1, a1))
        Hyprland.dispatch(root._text(d2, a2))
    }
}
