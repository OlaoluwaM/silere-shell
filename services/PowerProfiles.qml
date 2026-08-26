pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool available: SystemTools.hasPowerProfilesCtl
    readonly property bool syncing: _get.running || _set.running || _list.running
        || _getRetry.running
    property string profile: ""
    property string lastError: ""

    // the daemon reports an active profile it is not actually delivering (lap mode, thermals);
    // the reason string is empty whenever it is delivering, so absence fails closed to "fine"
    property string _degradedReason: ""
    readonly property bool degraded: profile === "performance" && _degradedReason.length > 0

    readonly property string label: profile === "performance" ? "Performance"
                                  : profile === "power-saver" ? "Power Saver"
                                  : profile === "balanced"    ? "Balanced"
                                  : profile.length > 0        ? profile.replace(/-/g, " ") : ""
    readonly property string glyph: profile === "performance" ? "󰓅"
                                  : profile === "power-saver" ? "󰾆" : "󰾅"

    property int _writeGen: 0
    property bool _correctiveRefreshPending: false
    // a read error is cleared by the next good read; a set error is not, so the two cannot share a string test
    property bool _readError: false

    property int _getRetries: 0
    readonly property int _getRetryMax: 4
    // the three every powerprofilesctl build knows; only a fallback now that the daemon is asked
    readonly property var _knownProfiles: ["balanced", "performance", "power-saver"]
    // what this machine actually offers: a laptop with no platform_profile has no "performance",
    // and cycling onto one the daemon rejects flips the row to a mode it then has to take back
    property var profiles: []
    readonly property var _cycleOrder: {
        const found = root.profiles
        if (found.length === 0) return _list.running ? [] : root._knownProfiles
        // keep the familiar balanced/performance/power-saver rotation, then anything exotic
        const ordered = root._knownProfiles.filter(p => found.indexOf(p) >= 0)
        return ordered.concat(found.filter(p => root._knownProfiles.indexOf(p) < 0))
    }
    Timer {
        id: _getRetry
        interval: 600
        onTriggered: {
            if (_get.running || _set.running) {
                restart()
                return
            }
            root.refresh()
        }
    }

    function refresh(): void {
        if (!available || _get.running || _set.running) return
        _get._corrective = root._correctiveRefreshPending
        _correctiveRefreshPending = false
        _get._gen = root._writeGen
        _get.exec(["powerprofilesctl", "get"])
    }

    function _refreshDegraded(): void {
        if (root.profile !== "performance") {
            if (_degradedProc.running) _degradedProc.running = false
            root._degradedReason = ""
            return
        }
        if (!SystemTools.hasBusctl) {
            root._degradedReason = ""
            return
        }
        if (_degradedProc.running) return
        // the daemon owns both names; the newer one first, the pre-0.20 name as fallback
        _degradedProc.exec(["bash", "-c",
            "busctl get-property org.freedesktop.UPower.PowerProfiles" +
            " /org/freedesktop/UPower/PowerProfiles" +
            " org.freedesktop.UPower.PowerProfiles PerformanceDegraded 2>/dev/null" +
            " || busctl get-property net.hadess.PowerProfiles" +
            " /net/hadess/PowerProfiles" +
            " net.hadess.PowerProfiles PerformanceDegraded 2>/dev/null"])
    }

    function _queueCorrectiveRefresh(): void {
        root._correctiveRefreshPending = true
        root._getRetries = 0
        _getRetry.restart()
    }

    function _parseProfile(value): string {
        const profile = SafeText.singleLineText(value, 64)
        return root._cycleOrder.indexOf(profile) >= 0 ? profile : ""
    }

    // `powerprofilesctl list` indents each name and marks the active one with "*":
    //   * balanced:
    //       CpuDriver: amd_pstate
    function _parseProfileList(value): var {
        const out = []
        const lines = SafeText.boundedText(value, 4096).split("\n")
        for (const line of lines) {
            const m = /^[\s*]*([a-z][a-z-]{0,30}):\s*$/.exec(line)
            if (m && out.indexOf(m[1]) < 0) out.push(m[1])
            if (out.length >= 8) break
        }
        return out
    }

    function _discoverProfiles(): void {
        if (!available || _list.running || root.profiles.length > 0) return
        _list.exec(["powerprofilesctl", "list"])
    }

    // busctl prints a typed property as: s "reason"
    function _parseDegraded(value): string {
        const line = SafeText.singleLineText(value, 160)
        const m = /^s\s+"(.*)"$/.exec(line)
        return m ? SafeText.singleLineText(m[1], 64) : ""
    }

    function cycle(): void {
        // _set.running guard: exec while a set's in flight drops the write but still flips the optimistic profile — UI and daemon diverge
        if (!available || profile === "" || _set.running) return
        const order = root._cycleOrder
        const at = order.indexOf(profile)
        if (order.length < 2 || at < 0) return
        const next = order[(at + 1) % order.length]
        profile = next
        root._readError = false
        root.lastError = ""
        root._writeGen++
        _set.exec(["powerprofilesctl", "set", next])
    }

    readonly property bool _watched: ControlSurfaces.anyOpen
    on_WatchedChanged: if (!root._watched && !root._correctiveRefreshPending) _getRetry.stop()

    function _surfaceOpened(): void {
        root._getRetries = 0
        root._discoverProfiles()
        root.refresh()
    }

    function _syncToolAvailability(): void {
        if (!SystemTools.ready) return
        if (root.available) {
            if (root._watched) {
                root._discoverProfiles()
                root.refresh()
            }
            return
        }

        _getRetry.stop()
        if (_get.running) _get.running = false
        if (_set.running) _set.running = false
        if (_degradedProc.running) _degradedProc.running = false
        if (_list.running) _list.running = false
        root.profiles = []
        root._getRetries = 0
        root._correctiveRefreshPending = false
        root._readError = false
        root.profile = ""
        root._degradedReason = ""
        root.lastError = ""
    }

    Connections {
        target: ControlSurfaces
        function onOpened() { root._surfaceOpened() }
    }
    Connections {
        target: SystemTools
        function onReadyChanged() { root._syncToolAvailability() }
        function onScanRevisionChanged() { root._syncToolAvailability() }
    }
    BoundedProcess {
        id: _get
        property int _gen: 0
        property bool _corrective: false
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _getOut }
        onTimeoutReached: {
            root._readError = true
            root.lastError = "Power mode check timed out"
        }
        onExited: (code) => {
            if (!root.available) return
            if (_set.running || _gen !== root._writeGen) return
            if (code === 0) {
                const p = root._parseProfile(_getOut.text)
                if (p.length > 0) {
                    root.profile = p
                    root._refreshDegraded()
                    root._getRetries = 0
                    root._correctiveRefreshPending = false
                    if (root._readError) {
                        root._readError = false
                        root.lastError = ""
                    }
                    return
                }
            }
            const shouldRetry = root.profile === "" || _corrective
            if (shouldRetry && root.available && (root._watched || _corrective)
                    && root._getRetries < root._getRetryMax) {
                root._getRetries++
                root._correctiveRefreshPending = _corrective
                _getRetry.restart()
                return
            }
            if (shouldRetry && !timedOut) {
                root._readError = true
                root.lastError = "Could not verify the power mode"
            }
        }
    }
    BoundedProcess {
        id: _list
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _listOut }
        onExited: (code) => {
            if (!root.available) return
            if (!timedOut && code === 0) {
                const found = root._parseProfileList(_listOut.text)
                if (found.length > 0) root.profiles = found
            }
            if (root.profile === "" && root._watched && !_get.running && !_set.running) {
                _getRetry.stop()
                root._getRetries = 0
                root.refresh()
            }
        }
    }
    BoundedProcess {
        id: _degradedProc
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _degradedOut }
        onTimeoutReached: root._degradedReason = ""
        onExited: (code) => {
            if (!root.available) {
                root._degradedReason = ""
                return
            }
            root._degradedReason = (root.profile === "performance" && code === 0 && !timedOut)
                ? root._parseDegraded(_degradedOut.text) : ""
        }
    }
    BoundedProcess {
        id: _set
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        stderr: StdioCollector { id: _setErr }
        onTimeoutReached: {
            root._readError = false
            root.lastError = "Power mode change timed out"
        }
        onExited: (code) => {
            if (!root.available) return
            if (timedOut) {
                root._queueCorrectiveRefresh()
                return
            }
            if (code === 0) {
                root._readError = false
                root.lastError = ""
                root._queueCorrectiveRefresh()
                return
            }
            // the row re-reads the daemon, so a swallowed failure just flips the label back with no reason given
            root._readError = false
            root.lastError = SafeText.boundedText(
                _setErr.text.trim().split("\n").pop() || "Could not change the power mode", 160)
            root._queueCorrectiveRefresh()
        }
    }
}
