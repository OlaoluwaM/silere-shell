pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../services"

// The wallpaper command measures the wallpaper and leaves this small file beside the
// shell's settings; the shell never samples pixels itself. Same contract shape as the
// matugen palette: a missing file is the stock look, a bad write keeps the last good
// values, and the deployment is the only writer.
Singleton {
    id: root

    readonly property string samplePath: XdgPaths.configHome.length > 0
        ? XdgPaths.configHome + "/silere-shell/glass.json" : ""

    property var _sample: ({})
    property bool _everLoaded: false
    readonly property bool usingFallback: !root._everLoaded
    // a later bad write keeps the last good sample, which is right, but then the glass
    // stops following the wallpaper and usingFallback stays false -- the shell has to say why
    property bool sampleStale: false

    readonly property var _regions: ["top", "bottom", "field"]
    // the menu's corner under each bar position, with its brightest tenth (ADR 0005). Optional,
    // so a sample written before the sampler measured them still loads and the menu reads field
    readonly property var _peakRegions: ["menuTop", "menuBottom"]
    // quiet mid-grey so every binding below is defined before a sample lands; Theme never
    // paints from it, since its adaptive branch waits on usingFallback
    readonly property var _fallbackRegion: ({ luminance: 0.30, noise: 0.10, tone: "" })

    // both edges and both menu corners are exposed and Theme picks by bar position: selecting
    // here would route a bar-position flip through the Behaviors below, and a settings flip must
    // snap (ADR 0001) while only a wallpaper change eases
    readonly property var _top:    root._sample.top    ?? root._fallbackRegion
    readonly property var _bottom: root._sample.bottom ?? root._fallbackRegion
    readonly property var _field:  root._sample.field  ?? root._fallbackRegion
    readonly property var _menuTop:    root._sample.menuTop    ?? null
    readonly property var _menuBottom: root._sample.menuBottom ?? null

    // Plain properties, not readonly: the Behaviors below ease a wallpaper-driven sample
    // swap at the source (ADR 0001), so every Theme color derived from these fades once.
    // Nothing may assign these imperatively -- that would destroy the bindings for good.
    property real  topLuminance:    root._top.luminance
    property real  topNoise:        root._top.noise
    property color topTone:         root._top.tone    || MatugenTheme.background
    property real  bottomLuminance: root._bottom.luminance
    property real  bottomNoise:     root._bottom.noise
    property color bottomTone:      root._bottom.tone || MatugenTheme.background
    property real  fieldLuminance:  root._field.luminance
    property real  fieldNoise:      root._field.noise
    property color fieldTone:       root._field.tone  || MatugenTheme.background
    property real  menuTopPeak:     root._menuTop    ? root._menuTop.peak     : root._field.luminance
    property real  menuTopNoise:    root._menuTop    ? root._menuTop.noise    : root._field.noise
    property color menuTopTone:     (root._menuTop    ? root._menuTop.tone    : root._field.tone) || MatugenTheme.background
    property real  menuBottomPeak:  root._menuBottom ? root._menuBottom.peak  : root._field.luminance
    property real  menuBottomNoise: root._menuBottom ? root._menuBottom.noise : root._field.noise
    property color menuBottomTone:  (root._menuBottom ? root._menuBottom.tone : root._field.tone) || MatugenTheme.background

    // gated on _everLoaded for the same reason as the palette: launch must snap, not
    // cross-fade from the fallback to the on-disk sample
    MotionBehavior on topLuminance {
        gate: root._everLoaded
        NumberAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on topNoise {
        gate: root._everLoaded
        NumberAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on topTone {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on bottomLuminance {
        gate: root._everLoaded
        NumberAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on bottomNoise {
        gate: root._everLoaded
        NumberAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on bottomTone {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on fieldLuminance {
        gate: root._everLoaded
        NumberAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on fieldNoise {
        gate: root._everLoaded
        NumberAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on fieldTone {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on menuTopPeak {
        gate: root._everLoaded
        NumberAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on menuTopNoise {
        gate: root._everLoaded
        NumberAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on menuTopTone {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on menuBottomPeak {
        gate: root._everLoaded
        NumberAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on menuBottomNoise {
        gate: root._everLoaded
        NumberAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }
    MotionBehavior on menuBottomTone {
        gate: root._everLoaded
        ColorAnimation { duration: Motion.palette; easing.type: Easing.OutCubic }
    }

    // the sample lands a beat after the palette (the wallpaper command writes it last), so
    // the leaf fades need their own hold or they double-ease the tail of this swap
    readonly property bool transitioning: _transitionHold.running
    Timer { id: _transitionHold; interval: Motion.palette }

    function _unit(v: var): bool {
        return typeof v === "number" && isFinite(v) && v >= 0 && v <= 1
    }

    function _parseRegion(raw: var): var {
        if (raw === null || typeof raw !== "object" || Array.isArray(raw))
            return null
        if (!root._unit(raw.luminance) || !root._unit(raw.noise))
            return null
        if (typeof raw.tone !== "string" || !/^#[0-9a-fA-F]{6}$/.test(raw.tone))
            return null
        return { luminance: raw.luminance, noise: raw.noise, tone: raw.tone }
    }

    function _parsePeakRegion(raw: var): var {
        const region = root._parseRegion(raw)
        if (region === null || !root._unit(raw.peak))
            return null
        region.peak = raw.peak
        return region
    }

    function _parseSample(raw: string): var {
        let parsed
        try {
            parsed = JSON.parse(raw || "")
        } catch (e) {
            return null
        }
        if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object")
            return null
        if (parsed.version !== 1)
            return null
        const clean = Object.create(null)
        for (let i = 0; i < root._regions.length; i++) {
            const region = root._parseRegion(parsed[root._regions[i]])
            if (region === null)
                return null
            clean[root._regions[i]] = region
        }
        // absent is fine, malformed is not: half a menu region would move the pane on a guess
        for (let i = 0; i < root._peakRegions.length; i++) {
            const name = root._peakRegions[i]
            if (parsed[name] === undefined)
                continue
            const region = root._parsePeakRegion(parsed[name])
            if (region === null)
                return null
            clean[name] = region
        }
        return clean
    }

    function _changed(a: var, b: var): bool {
        for (let i = 0; i < root._regions.length; i++) {
            const x = a[root._regions[i]], y = b[root._regions[i]]
            if (!x || x.luminance !== y.luminance || x.noise !== y.noise || x.tone !== y.tone)
                return true
        }
        for (let i = 0; i < root._peakRegions.length; i++) {
            const x = a[root._peakRegions[i]], y = b[root._peakRegions[i]]
            if (!x !== !y)
                return true
            if (x && (x.luminance !== y.luminance || x.noise !== y.noise
                    || x.tone !== y.tone || x.peak !== y.peak))
                return true
        }
        return false
    }

    function _load(raw: string): void {
        const parsed = root._parseSample(raw)
        // keep the last valid sample during an editor save or atomic replace; a malformed external file must never move the glass
        if (parsed === null) {
            root.sampleStale = root._everLoaded
            return
        }
        // arm the leaf-fade hold only when a value actually changes: a byte-identical
        // rewrite (the same wallpaper re-applied) must not suppress hover fades for nothing
        if (root._everLoaded && Motion.palette > 0 && root._changed(root._sample, parsed))
            _transitionHold.restart()
        root._sample = parsed
        root._everLoaded = true
        root.sampleStale = false
    }

    function _markUnreadable(): void {
        // missing on first launch is the stock look. Disappearing after a good load means the glass on screen is now a retained copy
        root.sampleStale = root._everLoaded
    }

    FileView {
        id: _sampleFile
        path: root.samplePath
        watchChanges: true
        printErrors: false
        onLoaded: root._load(_sampleFile.text() || "")
        onFileChanged: reload()
        onLoadFailed: root._markUnreadable()
    }
}
