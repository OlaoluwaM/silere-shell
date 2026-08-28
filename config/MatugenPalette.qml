pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The singleton itself is shipped and immutable. Matugen writes only the small
// per-user JSON palette below, which also works when Silere lives in /usr/share.
Singleton {
    id: root

    readonly property string palettePath: {
        const configured = String(Quickshell.env("XDG_CONFIG_HOME") || "").trim()
        if (configured.startsWith("/")) return configured + "/matugen/silere-shell.json"
        const home = String(Quickshell.env("HOME") || "").trim()
        return home.startsWith("/") ? home + "/.config/matugen/silere-shell.json" : ""
    }

    property var _palette: ({})
    property bool _everLoaded: false
    readonly property bool usingFallback: !root._everLoaded
    // a later bad write keeps the last good colors, which is right, but then nothing
    // moves on screen and usingFallback stays false — the shell has to say why
    property bool paletteStale: false
    readonly property var _fallback: ({
        background: "#101116",
        surface:    "#1d1f26",
        text:       "#e9eaf0",
        subtext:    "#a0a4b0",
        accent:     "#9babe9",
        error:      "#dd92a2",
        warning:    "#d4ad77",
        success:    "#94bd8b"
    })
    readonly property var _roles: [
        "background", "surface", "text", "subtext",
        "accent", "error", "warning", "success"
    ]

    // Plain properties, not readonly: the Behaviors below intercept the binding
    // writes to interpolate a wallpaper-driven palette swap (ADR 0001). Nothing
    // may assign these imperatively — that would destroy the bindings for good.
    property color background: _palette.background ?? _fallback.background
    property color surface:    _palette.surface    ?? _fallback.surface
    property color text:       _palette.text       ?? _fallback.text
    property color subtext:    _palette.subtext    ?? _fallback.subtext
    property color accent:     _palette.accent     ?? _fallback.accent
    property color error:      _palette.error      ?? _fallback.error
    property color warning:    _palette.warning    ?? _fallback.warning
    property color success:    _palette.success    ?? _fallback.success

    // MotionBehavior, never ColorFade: ColorFade's default gate reads
    // `transitioning`, so it would disable these exact animations the moment a
    // transition started. Gating on _everLoaded keeps launch a snap — the shell
    // must not cross-fade from the built-in fallback to the on-disk palette.
    MotionBehavior on background {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on surface {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on text {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on subtext {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on accent {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on error {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on warning {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on success {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }

    // leaf ColorFades read this to stand down while the sources move; a Timer
    // approximating the window beats wiring into eight animation jobs (see the
    // settle() history comment in MotionBehavior.qml for why that cleverness
    // is off the table)
    readonly property bool transitioning: _transitionHold.running
    Timer { id: _transitionHold; interval: Motion.palette }

    function _parsePalette(raw: string): var {
        let parsed
        try {
            parsed = JSON.parse(raw || "")
        } catch (e) {
            return null
        }
        if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object")
            return null
        const clean = Object.create(null)
        for (let i = 0; i < root._roles.length; i++) {
            const role = root._roles[i]
            const value = parsed[role]
            if (typeof value !== "string" || !/^#[0-9a-fA-F]{6}$/.test(value))
                return null
            clean[role] = value
        }
        return clean
    }

    function _load(raw: string): void {
        const parsed = root._parsePalette(raw)
        // keep the last valid palette during an editor save or atomic replace; a malformed external file must never partially recolor the shell
        if (parsed === null) {
            root.paletteStale = root._everLoaded
            return
        }
        // arm the leaf-fade gate only when a color actually changes: a
        // byte-identical rewrite (the same wallpaper re-applied as a repair
        // action) must not suppress hover fades for nothing
        if (root._everLoaded && Motion.palette > 0
                && root._roles.some(r => root._palette[r] !== parsed[r]))
            _transitionHold.restart()
        root._palette = parsed
        root._everLoaded = true
        root.paletteStale = false
    }

    function _markUnreadable(): void {
        // missing on first launch is the normal bundled fallback. Disappearing after a good load means the colors on screen are now a retained copy
        root.paletteStale = root._everLoaded
    }

    FileView {
        id: _paletteFile
        path: root.palettePath
        watchChanges: true
        printErrors: false
        onLoaded: root._load(_paletteFile.text() || "")
        onFileChanged: reload()
        onLoadFailed: root._markUnreadable()
    }
}
