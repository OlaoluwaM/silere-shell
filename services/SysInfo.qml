pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real memTotalKb: 0
    property real memAvailKb: 0
    property real uptimeSecs: 0
    property real diskUsedKb: 0
    property real diskTotalKb: 0
    property real cpuPct: 0
    property real _lastCpuTotal: 0
    property real _lastCpuIdle: 0

    readonly property real memPct:     memTotalKb > 0 ? (memTotalKb - memAvailKb) / memTotalKb : 0
    readonly property real diskPct:    diskTotalKb > 0 ? diskUsedKb / diskTotalKb : 0

    readonly property string uptimeLabel: {
        if (uptimeSecs <= 0) return "—"
        const s = Math.floor(uptimeSecs)
        if (s < 60) return s + "s"
        const d = Math.floor(s / 86400)
        const h = Math.floor((s % 86400) / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    property bool _active: false
    // The home menu wants a snappy 2s tick; the bar's vitals chips only need to notice
    // a threshold crossing within a handful of seconds, so they get a slower cadence.
    // Power tradeoff: leaving this gated on the menu alone would let the vitals widget
    // sit dark whenever the menu is closed, defeating its purpose, so presence in the
    // bar layout keeps /proc/meminfo and /proc/stat polling in the background at 6s —
    // two cheap reads, no process spawn — for as long as the widget could be visible.
    // Idle still pauses it entirely, and disk's df spawn stays behind the menu below.
    readonly property bool _vitalsPlaced: ShellSettings.barWidgetPlaced("vitals")
    readonly property bool _wanted: (MenuState.homeActive || root._vitalsPlaced) && !Idle.isIdle
    readonly property int _pollInterval: MenuState.homeActive ? 2000 : 6000

    on_WantedChanged: {
        if (_wanted) _startDelay.restart()
        else root._deactivate()
    }

    // already polling for the vitals widget when the menu opens: catch disk up immediately
    // instead of leaving it showing "—" for up to 10s until the gated slow timer first fires
    Connections {
        target: MenuState
        function onHomeActiveChanged() { if (MenuState.homeActive && root._active) root._refreshSlow() }
    }

    function _activate(): void {
        if (_active) return
        _active = true
        _refreshFast()
        _refreshSlow()
        // cpuPct is a delta between two /proc/stat reads; without a quick second sample the tile shows the last session's figure
        _cpuPrime.restart()
    }

    function _deactivate(): void {
        _startDelay.stop()
        _cpuPrime.stop()
        _active = false
        _lastCpuTotal = 0
        _lastCpuIdle = 0
        if (_slowProc.running) _slowProc.running = false
    }

    // created lazily on first open, after open already flipped true, catch that missed edge
    Component.onCompleted: if (_wanted) _startDelay.restart()

    Timer { id: _startDelay; interval: 120; onTriggered: root._activate() }
    Timer { id: _cpuPrime; interval: 250; onTriggered: if (root._active) _statFile.reload() }

    Timer {
        id: _poll
        interval: root._pollInterval
        repeat: true
        running: root._active
        onTriggered: root._refreshFast()
    }

    // disk isn't part of the vitals chips' contract, so its df spawn stays gated to the
    // home menu instead of running for the vitals widget's whole time on the bar
    Timer {
        id: _slowPoll
        interval: 10000
        repeat: true
        running: root._active && MenuState.homeActive
        onTriggered: root._refreshSlow()
    }

    FileView {
        id: _meminfoFile
        path: "/proc/meminfo"
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root._applyMeminfo(_meminfoFile.text())
    }

    FileView {
        id: _uptimeFile
        path: "/proc/uptime"
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root._applyUptime(_uptimeFile.text())
    }

    FileView {
        id: _statFile
        path: "/proc/stat"
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root._applyCpuStat(_statFile.text())
    }

    function _refreshFast(): void {
        if (!_active) return
        _meminfoFile.reload()
        _uptimeFile.reload()
        _statFile.reload()
    }

    function _applyMeminfo(mem: string): void {
        if (!root._active) return
        const total = mem.match(/^MemTotal:\s+(\d+)/m)
        const avail = mem.match(/^MemAvailable:\s+(\d+)/m)
        if (total && avail) {
            root.memTotalKb = parseInt(total[1]) || 0
            root.memAvailKb = parseInt(avail[1]) || 0
        }
    }

    function _applyUptime(raw: string): void {
        if (!root._active) return
        const up = raw.trim().split(/\s+/)
        if (up.length > 0) root.uptimeSecs = parseFloat(up[0]) || 0
    }

    function _applyCpuStat(_cpuRaw: string): void {
        if (!root._active) return
        const _cpuNl  = _cpuRaw.indexOf('\n')
        const cpuLine = _cpuNl < 0 ? _cpuRaw.trim() : _cpuRaw.slice(0, _cpuNl)
        const p = cpuLine.trim().split(/\s+/)
        if (p.length >= 9 && p[0] === "cpu") {
            const vals = []
            for (let i = 1; i <= 8; i++) vals.push(parseInt(p[i]) || 0)
            const idle  = vals[3] + vals[4]
            const total = vals.reduce((s, v) => s + v, 0)
            if (root._lastCpuTotal > 0 && total > root._lastCpuTotal) {
                const dTotal = total - root._lastCpuTotal
                const dIdle  = idle  - root._lastCpuIdle
                root.cpuPct = Math.max(0, Math.min(1, (dTotal - dIdle) / dTotal))
            }
            root._lastCpuTotal = total
            root._lastCpuIdle  = idle
        }
    }

    function _refreshSlow(): void {
        if (_slowProc.running) return
        _slowProc.exec(["bash", "-c",
            "df -k / 2>/dev/null | { " +
            "  read -r _; " +
            "  read -r _ total used _; " +
            "  [ -n \"$total\" ] && printf 'd%s %s\\n' \"$used\" \"$total\"; " +
            "}"])
    }

    Process {
        id: _slowProc
        stdout: SplitParser {
            onRead: (line) => {
                if (!root._active) return
                if (line.startsWith("d")) {
                    const p = line.slice(1).trim().split(/\s+/)
                    if (p.length >= 2) {
                        root.diskUsedKb  = parseInt(p[0]) || 0
                        root.diskTotalKb = parseInt(p[1]) || 0
                    }
                }
            }
        }
        Component.onDestruction: running = false
    }
}
