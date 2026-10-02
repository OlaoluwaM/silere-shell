pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    // the lua config framework replaces the plain dispatchers; CompositorHyprland binds this to
    // hyprland's own answer, so the two dispatch forms never rest on a guess about the config file
    property bool useLua: false

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
        if (dispatcher === "exit")
            return "hl.dsp.exit()"
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

    // an argv rather than a dispatch: the power rail runs it through SystemTools.runOrNotify so a
    // failure is reported. The script hands off to hyprshutdown when installed, which lets apps close
    // first as Hyprland's default quit bind does, then runs `command`; without it, a log out falls
    // back to this exit dispatcher and the others to `command` alone
    function sessionEndCommand(action: string, command): var {
        return ["bash", Quickshell.shellDir + "/scripts/hypr-session-end.sh", action,
            root._text("exit", "")].concat(command)
    }

    function exitCommand(): var {
        return root.sessionEndCommand("logout", [])
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
