import QtQuick
import Quickshell
import "services"

// a write's result routes by device through the real process exit, so the stand-in
// brightnessctl on PATH holds the first write until this probe has switched displays
ShellRoot {
    id: root

    property int phase: 0
    property int waited: 0
    property int failures: 0

    function check(ok: bool, label: string): void {
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    function finish(): void {
        console.log("PROBE-BRIGHTNESS-WRITE " + (root.failures ? "failed" : "passed"))
        _ticks.stop()
    }

    // the stand-in's sysfs paths never read: each failed read zeroes a reading and drops
    // readiness a moment later, and would relist the host's backlights and select one,
    // resetting the error this probe watches
    function standIn(device: string): void {
        Brightness._reprobeAttempts = 3
        Brightness._device = device
    }
    // readings a failed read took away, restored once that failure has landed
    function rearm(): void {
        Brightness.maxBrightness = 100
        Brightness.currentBrightness = 50
        Brightness.ready = true
    }

    Timer {
        id: _ticks
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            if (root.phase === 0) {
                // the tool scan has to find the stand-in first; one more tick then lets the
                // host's own device listing land before the stand-in replaces it
                if (!SystemTools.ready || !Brightness.toolAvailable) {
                    if (++root.waited < 20) return
                    root.check(false, "the stand-in brightnessctl is detected on PATH")
                    root.finish()
                    return
                }
                root.phase = 1
                return
            }
            // a write only starts the tick after its display was stood in or last written to,
            // once the failed reads have landed; the stand-in holds the first write until the
            // probe releases it after the switch, and the second returns at once
            switch (root.phase++) {
            case 1:
                root.standIn("probe-a")
                break
            case 2:
                root.rearm()
                Brightness.setPercent(60)
                break
            case 3:
                Brightness.devices = [{ name: "probe-b", type: "raw", max: 100 }]
                Brightness._selectDevice()
                root.check(Brightness._device === "probe-b" && Brightness.lastError === "",
                    "the display switches while the first write is in flight")
                Quickshell.execDetached(["touch",
                    Quickshell.env("SILERE_BRIGHTNESS_PROBE_ROOT") + "/release-probe-a"])
                break
            case 4:
                root.check(Brightness.lastError === "",
                    "a failed write to the display no longer selected leaves the new display's status alone")
                root.rearm()
                Brightness.setPercent(70)
                break
            case 5:
                root.check(Brightness.lastError === "Permission denied",
                    "a failed write to the current display reports through the process exit")
                root.finish()
                break
            }
        }
    }
}
