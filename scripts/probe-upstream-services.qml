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

        console.log("PROBE-UPSTREAM-SERVICES " + (failures === 0 ? "passed " : "failed ")
            + checks + " checks")
    }
}
