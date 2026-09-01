pragma Singleton

// Wallpaper picker backend. Dormant unless ShellSettings.wallpaperCommand is non-empty --
// packaging-only, same contract as Recording.qml's recordingStopCommand: with nothing to
// shell out to on a pick, the popup (and its IPC toggle) have nothing useful to do.
// wallpapersDir is a separate gate: it decides whether there is anything to *scan*, not
// whether the feature exists at all.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool available: ShellSettings.wallpaperCommand.trim().length > 0

    readonly property string _dir: ShellSettings.wallpapersDir.trim()
    readonly property var _extensions: ["png", "jpg", "jpeg", "webp", "avif", "bmp"]

    // "unconfigured" | "missing" | "empty" | "ok"
    property string state: "unconfigured"
    property var entries: []
    property bool scanning: false

    function _findArgs(): var {
        const args = ["find", root._dir, "-maxdepth", "1", "-type", "f", "("]
        for (let i = 0; i < root._extensions.length; i++) {
            if (i > 0) args.push("-o")
            args.push("-iname")
            args.push("*." + root._extensions[i])
        }
        args.push(")", "-printf", "%T@\t%p\n")
        return args
    }

    // newest-first, name as tiebreak for entries sharing an mtime
    function _parse(text: string): var {
        const lines = String(text || "").split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            if (line.length === 0) continue
            const tab = line.indexOf("\t")
            if (tab < 0) continue
            const mtime = parseFloat(line.slice(0, tab))
            const path = line.slice(tab + 1)
            if (!isFinite(mtime) || path.length === 0) continue
            const slash = path.lastIndexOf("/")
            const name = slash >= 0 ? path.slice(slash + 1) : path
            // lowercased once per scan: the popup's filter compares against this on
            // every keystroke, over every entry
            out.push({ path: path, name: name, nameLower: name.toLowerCase(), mtimeMs: mtime * 1000 })
        }
        out.sort((a, b) => b.mtimeMs - a.mtimeMs || a.name.localeCompare(b.name))
        return out
    }

    property bool _rescanPending: false
    // callbacks queued to run once the scan currently in flight (or the next one, if
    // none is running yet) lands -- random() rides this instead of duplicating rescan()'s
    // own in-flight/latest-wins bookkeeping
    property var _afterScan: []

    function _flushAfterScan(): void {
        const cbs = root._afterScan
        root._afterScan = []
        for (let i = 0; i < cbs.length; i++) cbs[i]()
    }

    function rescan(): void {
        if (root._dir.length === 0) {
            root.state = "unconfigured"
            root.entries = []
            root._flushAfterScan()
            return
        }
        if (_scanProc.running) { root._rescanPending = true; return }
        root.scanning = true
        root._scanFor = root._dir
        _scanProc.command = root._findArgs()
        _scanProc.running = true
    }

    // the directory the in-flight scan was launched against: settings.json hot-reloads,
    // so _dir can move (or empty) mid-scan, and results for a superseded directory must
    // not clobber whatever state the newer disposition already set
    property string _scanFor: ""

    BoundedProcess {
        id: _scanProc
        timeoutMs: 10000
        stdout: StdioCollector { id: _scanOut }
        stderr: StdioCollector { id: _scanErr }
        onExited: (code) => {
            root.scanning = false
            const rerun = root._rescanPending
            root._rescanPending = false
            if (root._scanFor !== root._dir) { root.rescan(); return }
            if (code !== 0) {
                root.state = "missing"
                root.entries = []
            } else {
                const parsed = root._parse(_scanOut.text)
                root.entries = parsed
                root.state = parsed.length === 0 ? "empty" : "ok"
            }
            // a rescan queued while this one was running wants fresher data than what
            // just landed -- let it run and let ITS exit flush the callbacks instead
            if (rerun) { root.rescan(); return }
            root._flushAfterScan()
        }
    }

    property string _pendingApplyPath: ""
    property bool _hasPendingApply: false

    function _startApply(path: string): void {
        // the queued path re-enters here from onExited, and the command can empty between
        // queueing and dequeueing: sh -c on an empty splice would try to execute the
        // image file itself, so the gate apply() promises has to hold here too
        if (!root.available) {
            root._hasPendingApply = false
            root._pendingApplyPath = ""
            return
        }
        // immediate feedback: failures are rare and the next pick self-corrects
        ShellSettings.wallpaperLast = path
        _applyProc.exec(["sh", "-c", ShellSettings.wallpaperCommand + ' "$1"', "wallpaper-apply", path])
    }

    // serialized, latest-wins: a burst of picks (arrow-key mashing, random spam) only
    // ever runs the most recent one once the in-flight command exits
    function apply(path: string): void {
        if (!root.available) return
        if (_applyProc.running) {
            root._pendingApplyPath = path
            root._hasPendingApply = true
            return
        }
        root._startApply(path)
    }

    BoundedProcess {
        id: _applyProc
        timeoutMs: 30000
        onExited: (code) => {
            if (root._hasPendingApply) {
                const next = root._pendingApplyPath
                root._hasPendingApply = false
                root._pendingApplyPath = ""
                root._startApply(next)
            }
        }
    }

    function _pickRandom(): void {
        if (root.entries.length === 0) return
        const idx = Math.floor(Math.random() * root.entries.length)
        root.apply(root.entries[idx].path)
    }

    // mirrors Caffeine.qml/Keybinds.qml's toggle IpcHandler: dormant/unreadable stays a
    // no-op so a chord can never open an empty or feature-off picker
    IpcHandler {
        target: "wallpapers"
        function toggle(): void { if (root.available) WallpapersPopupState.toggle() }
        function random(): void {
            if (!root.available) return
            root._afterScan.push(root._pickRandom)
            root.rescan()
        }
    }
}
