pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property string directory: XdgPaths.configHome.length > 0
        ? XdgPaths.configHome + "/silere-shell" : ""
    readonly property string settingsPath: directory.length > 0
        ? directory + "/settings.json" : ""
    readonly property string calendarMarksPath: directory.length > 0
        ? directory + "/calendar-marks.json" : ""
    readonly property string quickshellStatePath: XdgPaths.stateHome.length > 0
        ? XdgPaths.stateHome + "/quickshell/states.json" : ""

    property bool ready: false
    property string _error: ""
    readonly property string error: _error
    readonly property int maxDirectoryAttempts: 4

    property int _directoryFailures: 0

    function directoryRetryDelay(attempt: int): int {
        return Math.min(8000, 1000 * Math.pow(2, Math.max(0, attempt - 1)))
    }

    function _startDirectoryAttempt(): void {
        if (_mkdir.running) return
        if (root.directory.length === 0) {
            root._error = "No configuration directory is available."
            return
        }
        // a forced recheck follows a failed write: stop advertising readiness while it reruns
        root.ready = false
        _mkdir.running = true
    }

    function ensureDirectory(force): void {
        if (_mkdir.running || (root.ready && force !== true)) return
        if (_mkdirRetry.running && force !== true) return
        if (force === true || root._directoryFailures >= root.maxDirectoryAttempts) {
            _mkdirRetry.stop()
            root._directoryFailures = 0
        }
        root._startDirectoryAttempt()
    }

    Timer {
        id: _mkdirRetry
        interval: root.directoryRetryDelay(root._directoryFailures)
        repeat: false
        onTriggered: root._startDirectoryAttempt()
    }

    function _owned(path: string): bool {
        if (path === root.settingsPath || path === root.calendarMarksPath) return true
        if (root.directory.length === 0) return false
        const prefix = root.directory + "/settings."
        const suffix = ".bak.json"
        if (!path.startsWith(prefix) || !path.endsWith(suffix)) return false
        // a tag carrying a slash would chmod its way out of the store directory
        return /^[a-z0-9.-]+$/i.test(path.slice(prefix.length, path.length - suffix.length))
    }

    // stamped reset backups would otherwise accumulate forever
    function pruneBackups(): void {
        if (root.directory.length === 0) return
        Quickshell.execDetached(["bash", "-c",
            "cd -- \"$1\" 2>/dev/null || exit 0; "
            + "ls -1t settings.pre-reset*.bak.json 2>/dev/null | tail -n +6 | "
            + "while IFS= read -r f; do [ -L \"$f\" ] || rm -f -- \"$f\"; done",
            "bash", root.directory])
    }

    function hardenFile(path: string): void {
        // only files owned by this store may be chmodded. Keep the path as a separate argv entry so even unusual XDG paths never become syntax
        if (path.length === 0 || !root._owned(path)) return
        Quickshell.execDetached(["bash", "-c",
            "[ ! -L \"$1\" ] && chmod 0600 -- \"$1\"", "bash", path])
    }

    // PersistentProperties is managed by Quickshell rather than this store, and
    // Silere's notification history persists through it. Quickshell may create
    // the shared state file with the session umask (commonly 0644), so close the
    // directory once: a 0700 directory also covers a file written after this
    // runs, which chmod'ing the file alone cannot. Never follow a replacement
    // symlink and accept only the exact XDG-derived absolute path.
    function hardenQuickshellState(): void {
        const path = root.quickshellStatePath
        if (!path.startsWith("/")) return
        Quickshell.execDetached(["bash", "-c",
            "d=${1%/*}; [ -d \"$d\" ] && [ ! -L \"$d\" ] && chmod 0700 -- \"$d\"; "
            + "if [ -f \"$1\" ] && [ ! -L \"$1\" ]; then chmod 0600 -- \"$1\"; fi",
            "bash", path])
    }

    BoundedProcess {
        id: _mkdir
        timeoutMs: 10000
        command: ["bash", "-c",
            // without the exits, the trailing file check's status hides a failed mkdir
            "umask 077; mkdir -m 0700 -p -- \"$1\" || exit $?; " +
            "chmod 0700 -- \"$1\" || exit $?; " +
            "for f in \"$2\" \"$3\"; do " +
            "[ ! -e \"$f\" ] || [ -L \"$f\" ] || chmod 0600 -- \"$f\" || exit $?; done",
            "bash", root.directory, root.settingsPath, root.calendarMarksPath]
        onExited: code => {
            if (code === 0) {
                _mkdirRetry.stop()
                root._directoryFailures = 0
                root.ready = true
                root._error = ""
                return
            }

            root.ready = false
            root._error = "Could not create " + root.directory + "."
            root._directoryFailures++
            if (root._directoryFailures < root.maxDirectoryAttempts)
                _mkdirRetry.restart()
            console.warn("silere-shell: failed to create config directory:",
                root.directory)
        }
    }

    Component.onCompleted: root.ensureDirectory()
}
