pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Screen-recording indicator. Dormant unless GeneratedDefaults.recordingStateFile is
// non-empty: the Nix packaging is what makes the screenrecord wrapper create that path
// while wf-recorder runs and remove it (including on abort), so a plain checkout with
// no such wrapper just never sees a configured path and this singleton stays idle.
Singleton {
    id: root

    readonly property string _path: ShellSettings.recordingStateFile
    readonly property bool _enabled: root._path.length > 0
    // only spawn the watcher while something could actually show it, same conservation
    // as CpuTemp/SysInfo gating their own polling on ShellSettings.barWidgetPlaced
    readonly property bool _wanted: root._enabled && ShellSettings.barWidgetPlaced("privacy")
        && SystemTools.ready && SystemTools.hasInotifywait

    readonly property string _dir: {
        if (!root._enabled) return ""
        const i = root._path.lastIndexOf("/")
        return i > 0 ? root._path.slice(0, i) : "/"
    }
    readonly property string _base: {
        if (!root._enabled) return ""
        const i = root._path.lastIndexOf("/")
        return i >= 0 ? root._path.slice(i + 1) : root._path
    }

    property bool _exists: false
    readonly property bool recording: root._enabled && root._exists

    // one-shot existence check: driven at startup and every watcher (re)start, so a
    // recording already in progress before the shell/watcher came up is still seen
    function _restat(): void {
        if (!root._enabled) { root._exists = false; return }
        _stateFile.reload()
    }

    // _wanted alone only toggles the watcher on/off; it stays true across a path change
    // (recordingStateFile is schema-writable, so a hand-edited settings.json can swap it
    // live) and inotifywait has no reload signal for a new target directory. Killing the
    // child here leaves superviseWhen untouched, so SupervisedProcess's own crash-recovery
    // path (already the accepted worst case elsewhere in this file) brings it back within
    // restartDelay against the by-then-current command, instead of watching a directory
    // nothing points at anymore.
    readonly property string _watchTarget: root._dir + " " + root._base
    function _respawnWatcher(): void {
        if (_watcher.running) _watcher.running = false
    }

    Component.onCompleted: root._restat()
    on_PathChanged: root._restat()
    on_WantedChanged: if (root._wanted) root._restat()
    on_WatchTargetChanged: root._respawnWatcher()

    FileView {
        id: _stateFile
        path: root._enabled ? root._path : ""
        watchChanges: false
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root._exists = true
        onLoadFailed: root._exists = false
    }

    SupervisedProcess {
        id: _watcher
        // command stays a plain function of _dir, not of _wanted/superviseWhen -- gating
        // it on the same condition that flips superviseWhen would race two independent
        // bindings on the same signal (command might still hold its stale value the
        // instant onSuperviseWhenChanged fires and starts the process). superviseWhen
        // alone decides whether this ever runs, same split Screenshot.qml's watcher uses.
        superviseWhen: root._wanted
        restartDelay: 5000
        command: ["inotifywait", "-m", "-q", "-e", "create,delete,moved_to,moved_from",
            "--format", "%f", root._dir]
        stdout: SplitParser {
            onRead: line => { if (line === root._base) root._restat() }
        }
        onRunningChanged: if (running) root._restat()
    }
}
