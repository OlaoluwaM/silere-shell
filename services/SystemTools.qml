pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool ready: false
    property bool checking: false
    property string lastError: ""
    property var _tools: ({})
    // packageFamily left out on purpose: it fed the removed updater (see
    // docs/upstream-divergences.md), and nothing else reads it
    // ready stays true during a refresh so controls do not disappear. Consumers
    // that need to redo work after a coherent scan use this completion edge.
    property int _scanRevision: 0
    readonly property int scanRevision: _scanRevision

    readonly property bool probeFailed: ready && lastError.length > 0

    readonly property bool hasBrightnessctl: _tools.brightnessctl ?? false
    readonly property bool hasInotifywait:   _tools.inotifywait ?? false
    readonly property bool hasNmcli:         _tools.nmcli ?? false
    readonly property bool hasCava:          _tools.cava ?? false
    readonly property bool hasMatugen:       _tools.matugen ?? false
    readonly property bool hasHyprsunset:    _tools.hyprsunset ?? false
    readonly property bool hasHyprlock:      _tools.hyprlock ?? false
    readonly property bool hasSystemctl:     _tools.systemctl ?? false
    readonly property bool hasLoginctl:      _tools.loginctl ?? false
    readonly property bool hasHyprctl:       _tools.hyprctl ?? false
    readonly property bool hasNotifySend:    _tools["notify-send"] ?? false
    readonly property bool hasBusctl:        _tools.busctl ?? false
    readonly property bool hasPowerProfilesCtl: _tools.powerprofilesctl ?? false
    readonly property bool hasAsusctl:       _tools.asusctl ?? false
    readonly property bool hasFcList:        _tools["fc-list"] ?? false
    readonly property bool hasDbusMonitor:   _tools["dbus-monitor"] ?? false
    readonly property bool hasPwvucontrol:   _tools.pwvucontrol ?? false

    // "" | working | done | failed
    property string matugenRepairState: ""

    // the repair outlives the settings section that starts it; a page unload must not orphan the process or drop its result
    function repairMatugen(): void {
        if (root.matugenRepairState === "working") return
        root.matugenRepairState = "working"
        _matugenRepair.running = true
    }

    BoundedProcess {
        id: _matugenRepair
        timeoutMs: 15000
        command: ["bash", Quickshell.shellDir + "/scripts/install.sh", "--repair-matugen"]
        onExited: code => root.matugenRepairState = code === 0 ? "done" : "failed"
        onTimeoutReached: root.matugenRepairState = "failed"
        Component.onDestruction: running = false
    }

    function _shq(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // the power commands are already derived from these flags; this is the guard for a tool that went away between derivation and the click
    function commandAvailable(command): bool {
        if (!command || command.length === 0) return false
        const tool = String(command[0])
        if (tool === "hyprlock")  return root.hasHyprlock
        if (tool === "systemctl") return root.hasSystemctl
        if (tool === "loginctl")  return root.hasLoginctl
        return true
    }

    function runOrNotify(command, failTitle: string): void {
        if (!command || command.length === 0) return
        if (!root.hasNotifySend) {
            Quickshell.execDetached(command)
            return
        }
        const note = "notify-send --urgency=critical --app-name=silere-shell " +
            root._shq(failTitle) + " " + root._shq("It may require authorization or be blocked by a running task.")
        const argv = ["bash", "-c", '"$@" || ' + note, "bash"]
        for (let i = 0; i < command.length; i++) argv.push(String(command[i]))
        Quickshell.execDetached(argv)
    }

    function refresh(): void {
        if (_checkProc.running) return
        // keep the last confirmed capability set while refreshing. Features no longer disappear briefly when Settings triggers a fresh probe
        checking = true
        lastError = ""
        _checkProc.exec(["bash", "-c",
            "for t in brightnessctl inotifywait nmcli cava matugen hyprsunset hyprlock systemctl loginctl hyprctl notify-send " +
            "busctl powerprofilesctl asusctl fc-list dbus-monitor pwvucontrol; do " +
            "  command -v \"$t\" >/dev/null 2>&1 && echo \"$t\"; " +
            // the last lookup is optional; do not inherit its `command -v` status and discard every tool found before it
            "done; exit 0"])
    }

    Component.onCompleted: refresh()

    Process {
        id: _checkProc
        stdout: StdioCollector { id: _checkOut }
        onExited: (code) => {
            if (code !== 0) {
                // A refresh must not leave removed tools advertised forever.
                root._tools = ({})
                root.lastError = "Optional tool scan failed (exit " + code + ")"
                root.ready = true
                root.checking = false
                root._scanRevision++
                return
            }
            const found = {}
            const lines = (_checkOut.text || "").split(/\r?\n/)
            for (let i = 0; i < lines.length; i++) {
                const name = lines[i].trim()
                if (name.length > 0) found[name] = true
            }
            root._tools = found
            root.lastError = ""
            root.ready = true
            root.checking = false
            root._scanRevision++
        }
    }
}
