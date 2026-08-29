pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower as UPower

Singleton {
    id: root

    // the native service pushes reads; powerprofilesctl stays the write path so a
    // rejected change can report stderr
    readonly property bool available: SystemTools.hasPowerProfilesCtl
    readonly property bool syncing: _set.running
    property string lastError: ""

    function profileName(value): string {
        switch (value) {
        case UPower.PowerProfile.PowerSaver:  return "power-saver"
        case UPower.PowerProfile.Balanced:    return "balanced"
        case UPower.PowerProfile.Performance: return "performance"
        default:                              return ""
        }
    }

    readonly property string profile: root.available
        ? root.profileName(UPower.PowerProfiles.profile) : ""
    readonly property bool performanceAvailable: root.available
        && UPower.PowerProfiles.hasPerformanceProfile

    function cycleOrder(serviceAvailable: bool, hasPerformance: bool): var {
        if (!serviceAvailable) return []
        return hasPerformance
            ? ["balanced", "performance", "power-saver"]
            : ["balanced", "power-saver"]
    }

    readonly property var _cycleOrder: root.cycleOrder(
        root.available, root.performanceAvailable)

    function degradationActive(profileName: string, reason): bool {
        return profileName === "performance"
            && (reason === UPower.PerformanceDegradationReason.LapDetected
                || reason === UPower.PerformanceDegradationReason.HighTemperature)
    }

    readonly property bool degraded: root.available && root.degradationActive(
        root.profile, UPower.PowerProfiles.degradationReason)

    readonly property string label: profile === "performance" ? "Performance"
                                  : profile === "power-saver" ? "Power Saver"
                                  : profile === "balanced"    ? "Balanced"
                                  : ""
    readonly property string glyph: profile === "performance" ? "󰓅"
                                  : profile === "power-saver" ? "󰾆" : "󰾅"

    function cycle(): void {
        if (!root.available || root.profile.length === 0 || _set.running) return
        const order = root._cycleOrder
        const at = order.indexOf(root.profile)
        if (order.length < 2 || at < 0) return
        const next = order[(at + 1) % order.length]
        root.lastError = ""
        _set.exec(["powerprofilesctl", "set", next])
    }

    onAvailableChanged: if (!root.available) {
        if (_set.running) _set.running = false
        root.lastError = ""
    }

    BoundedProcess {
        id: _set
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        stderr: StdioCollector { id: _setErr }
        onTimeoutReached: root.lastError = "Power mode change timed out"
        onExited: (code) => {
            if (!root.available || timedOut) return
            root.lastError = code === 0 ? "" : SafeText.boundedText(
                _setErr.text.trim().split("\n").pop()
                    || "Could not change the power mode", 160)
        }
    }
}
