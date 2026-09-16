import QtQuick
import Quickshell
import "config"
import "services"

// Service regressions for the selected post-v1.0.0 upstream imports. These
// assertions stay hardware-free and exercise the public helper boundaries.
ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0

    function check(condition: bool, message: string): void {
        checks++
        if (!condition) {
            failures++
            console.warn("PROBE-FAIL " + message)
        }
    }

    Component.onCompleted: {
        check(SafeText.lastNonEmptyLine("noise\r\n  failure\u202E  \r\n\r\n", "fallback", 16)
                === "failure", "last error line handles CRLF and sanitizes controls")
        check(SafeText.lastNonEmptyLine(" \n\r\n", "fallback", 16) === "fallback",
            "last error line falls back for blank output")
        check(SafeText.lastNonEmptyLine("x".repeat(32), "fallback", 8).length === 8,
            "last error line stays bounded")

        const scrollKey = "upstream-services-reversal"
        check(Scroll._processDelta(60, scrollKey, 120, 2, 0) === 0
                && Scroll._processDelta(-120, scrollKey, 120, 2, 0) === -1,
            "reversing scroll discards the old partial notch")

        check(WindowActions._appMatches({ cls: "firefox", initialClass: "" }, "firefox")
                && !WindowActions._appMatches({ cls: "firefox", initialClass: "" }, "ox"),
            "short app names require an exact window-class match")

        check(Media.extrapolatedPosition(10, 5000, false, 2, 30) === 10
                && Media.extrapolatedPosition(10, 5000, true, 0.5, 30) === 12.5
                && Media.extrapolatedPosition(10, 5000, true, 1, 30) === 15
                && Media.extrapolatedPosition(10, 5000, true, 2, 30) === 20,
            "media progress uses playing state and playback rate")
        check(Media.extrapolatedPosition(28, 5000, true, 2, 30) === 30
                && Media.extrapolatedPosition(10, 5000, true, NaN, 30) === 15
                && Media.extrapolatedPosition(NaN, NaN, true, 1, 0) === 0,
            "media progress clamps duration and rejects invalid values")

        const toolsWas = SystemTools._tools
        const readyWas = SystemTools.ready
        const checkingWas = SystemTools.checking
        const errorWas = SystemTools.lastError
        const revisionWas = SystemTools._scanRevision
        const retryWas = SystemTools._retryDelayMs
        SystemTools._tools = { hyprctl: true }
        SystemTools.ready = false
        SystemTools.checking = true
        SystemTools._retryDelayMs = 0
        SystemTools._scanFailed("probe failure")
        check(SystemTools.ready && !SystemTools.checking && SystemTools._tools.hyprctl
                && SystemTools._retryDelayMs === SystemTools._minRetryDelayMs
                && SystemTools._scanRevision === revisionWas,
            "failed tool scans keep the last result and schedule a bounded retry")
        SystemTools._tools = toolsWas
        SystemTools.ready = readyWas
        SystemTools.checking = checkingWas
        SystemTools.lastError = errorWas
        SystemTools._scanRevision = revisionWas
        SystemTools._retryDelayMs = retryWas

        Hooks._runTimes = []
        Hooks._criticalTimes = []
        for (let i = 0; i < Hooks.maxRunsPerSecond; i++) Hooks._budgetAllows()
        check(!Hooks._budgetAllows() && Hooks._criticalAllows() && Hooks._criticalAllows()
                && !Hooks._criticalAllows(),
            "critical hooks retain a separate, bounded allowance after normal flooding")
        check(Hooks._groupWaitScript.indexOf("sleep 0.25") >= 0,
            "hook descendant polling uses the lower-frequency interval")
        Hooks._runTimes = []
        Hooks._criticalTimes = []

        console.log("PROBE-UPSTREAM-SERVICES " + (failures === 0 ? "passed " : "failed ")
            + checks + " checks")
    }
}
