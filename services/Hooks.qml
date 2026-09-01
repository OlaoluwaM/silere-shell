pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    readonly property string directory: ConfigStore.directory.length > 0
        ? ConfigStore.directory + "/hooks" : ""

    // the scan probes these names rather than listing the directory, so a file dropped there under any other name is never a path this can execute
    // no "update-available": the fork removed the updater (see docs/upstream-divergences.md)
    readonly property var events: [
        "battery-critical",
        "notification",
        "theme-changed",
        "workspace-changed"
    ]

    readonly property int maxArgChars: 512
    readonly property int maxArgs: 4

    readonly property int maxRunsPerSecond: 20
    readonly property int maxRuntimeMs: 30000
    // timeout owns a process group, while the inner shell stays alive until ordinary
    // background children leave it; otherwise timeout exits with the hook entrypoint
    readonly property int _containGraceMs: 2000
    readonly property bool _contained: SystemTools.hasTimeout
    readonly property string _groupWaitScript: '"$@"; code=$?; '
        + 'IFS= read -r own < /proc/self/stat || exit "$code"; '
        + 'self=${own%% *}; rest=${own##*) }; set -- $rest; group=$3; outer=$PPID; '
        + 'while :; do alive=false; for stat in /proc/[0-9]*/stat; do '
        + '[ -r "$stat" ] || continue; IFS= read -r line < "$stat" || continue; '
        + 'pid=${line%% *}; rest=${line##*) }; set -- $rest; '
        + '[ "${1:-}" != Z ] && [ "${3:-}" = "$group" ] '
        + '&& [ "$pid" != "$self" ] && [ "$pid" != "$outer" ] '
        + '&& { alive=true; break; }; done; $alive || exit "$code"; sleep 0.1; done'

    property var _present: ({})
    property var _found: ({})
    property bool _scanned: false
    property var _runTimes: []
    property bool _throttled: false
    readonly property bool armed: true

    Component.onCompleted: if (ConfigStore.ready) root.rescan()

    function has(event: string): bool {
        return root._present[event] === true
    }

    // a notification flood or a workspace event storm reaches here once per event; without a ceiling each one is another spawn
    function _budgetAllows(): bool {
        const now = Date.now()
        const recent = []
        for (let i = 0; i < root._runTimes.length; i++)
            if (now - root._runTimes[i] < 1000) recent.push(root._runTimes[i])
        if (recent.length >= root.maxRunsPerSecond) {
            root._runTimes = recent
            return false
        }
        recent.push(now)
        root._runTimes = recent
        return true
    }

    function fire(event: string, args): void {
        if (root._present[event] !== true) return
        if (!root._budgetAllows()) {
            if (!root._throttled) {
                root._throttled = true
                console.warn("silere-shell: hooks exceeded "
                    + root.maxRunsPerSecond + " runs/s; dropping until it settles")
            }
            return
        }
        root._throttled = false
        const argv = [root.directory + "/" + event]
        const list = args || []
        const n = Math.min(list.length, root.maxArgs)
        for (let i = 0; i < n; i++)
            argv.push(SafeText.singleLineText(String(list[i]), root.maxArgChars))
        if (!root._claimRunner(argv)) root._queue(event, argv)
    }

    // execDetached reports no exit, so a rate cap alone cannot bound how many are alive at once
    component HookRunner: BoundedProcess {
        id: runner
        property string hookPath: ""
        // only a backstop once `timeout` owns the deadline: killing the wrapper leaves the group
        // behind, so this must fire later than the wrapper's own term-then-kill window
        timeoutMs: root._contained
            ? root.maxRuntimeMs + root._containGraceMs + 3000
            : root.maxRuntimeMs
        onRunningChanged: if (!running) Qt.callLater(root._drain)
        onExited: (code) => {
            if (code === 124 || code === 128 + 9)
                console.warn("silere-shell: hook ran past "
                    + root.maxRuntimeMs + "ms and was terminated: " + runner.hookPath)
        }
        onTimeoutReached: console.warn("silere-shell: hook ran past "
            + runner.timeoutMs + "ms and was terminated: " + runner.hookPath)
    }

    property HookRunner _runner0: HookRunner {}
    property HookRunner _runner1: HookRunner {}
    property HookRunner _runner2: HookRunner {}
    property HookRunner _runner3: HookRunner {}
    readonly property var _runners: [_runner0, _runner1, _runner2, _runner3]

    property var _queued: ({})
    property var _queueOrder: []

    // seconds, and never below 1: `timeout 0` means "no limit"
    function _wrapArgv(argv): var {
        const secs = Math.max(1, Math.round(root.maxRuntimeMs / 1000))
        const grace = Math.max(1, Math.round(root._containGraceMs / 1000))
        return ["timeout", "--kill-after=" + grace, String(secs),
            "bash", "-c", root._groupWaitScript, "silere-hook"].concat(argv)
    }

    function _containedArgv(argv): var {
        return root._contained ? root._wrapArgv(argv) : argv
    }

    function _claimRunner(argv): bool {
        for (let i = 0; i < root._runners.length; i++) {
            const runner = root._runners[i]
            if (runner.running) continue
            runner.hookPath = argv[0]
            runner.command = root._containedArgv(argv)
            runner.running = true
            return true
        }
        return false
    }

    // a repeat of a waiting event is the same event: only the newest arguments are still true
    function _queue(event: string, argv): void {
        if (root._queued[event] === undefined) root._queueOrder.push(event)
        root._queued[event] = argv
    }

    function _drain(): void {
        while (root._queueOrder.length > 0) {
            if (!root._claimRunner(root._queued[root._queueOrder[0]])) return
            delete root._queued[root._queueOrder.shift()]
        }
    }

    function rescan(): void {
        if (root.directory.length === 0 || _scan.running) return
        root._found = ({})
        _scan.running = true
    }

    BoundedProcess {
        id: _scan
        timeoutMs: 5000
        command: ["bash", "-c",
            "d=\"$1\"; shift; cd -- \"$d\" 2>/dev/null || exit 0; "
            + "for f in \"$@\"; do [ -f \"$f\" ] && [ -x \"$f\" ] "
            + "&& printf '%s\\n' \"$f\"; done",
            "bash", root.directory].concat(root.events)
        // every write to _present rebinds all five hook targets; collect, then swap once
        stdout: SplitParser {
            onRead: line => {
                const name = line.trim()
                if (root.events.indexOf(name) < 0) return
                root._found[name] = true
            }
        }
        onExited: {
            root._present = Object.assign({}, root._found)
            root._found = ({})
            root._scanned = true
        }
    }

    Connections {
        target: ConfigStore
        function onReadyChanged() {
            if (ConfigStore.ready) root.rescan()
        }
    }

    // an unset hook leaves its target out of the binding entirely, so a service nothing else has built is not created just to be watched
    Connections {
        target: root._present["notification"] === true ? Notifications : null
        function onNotificationShown(appName, summary, critical) {
            root.fire("notification", [appName, summary, critical ? "critical" : "normal"])
        }
    }

    Connections {
        target: root._present["battery-critical"] === true ? Battery : null
        function onCriticalChanged() {
            if (Battery.critical) root.fire("battery-critical", [Battery.pct])
        }
    }

    // the accent rails write per pointer frame; fire on the colour the drag lands on
    Timer {
        id: _accentSettle
        interval: 400
        onTriggered: root.fire("theme-changed", [String(Theme.accent)])
    }

    Connections {
        target: root._present["theme-changed"] === true ? Theme : null
        function onAccentChanged() { _accentSettle.restart() }
    }

    Connections {
        target: root._present["workspace-changed"] === true ? Compositor : null
        // niri's ref is an internal id; wsId is the number on screen on both backends
        function onFocusedWorkspaceRefChanged() {
            root.fire("workspace-changed",
                [Compositor.activeWorkspaceId(Compositor.focusedMonitor)])
        }
    }

    IpcHandler {
        target: "hooks"

        function list(): string {
            if (root.directory.length === 0) return "no configuration directory"
            const out = []
            for (let i = 0; i < root.events.length; i++) {
                const e = root.events[i]
                out.push((root._present[e] === true ? "active  " : "unset   ") + e)
            }
            return root.directory + "\n" + out.join("\n")
        }

        function rescan(): string {
            root.rescan()
            return "ok"
        }
    }
}
