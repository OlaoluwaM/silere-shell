import QtQuick
import Quickshell
import Quickshell.Io
import "services"

// the stand-in systemctl, hyprctl and hyprsunset on PATH are the only commands NightLight can
// reach; this probe steers the stand-in unit through files and reads back what it was asked
ShellRoot {
    id: root

    readonly property string base: Quickshell.env("SILERE_NIGHTLIGHT_PROBE_ROOT")
    readonly property string checkError: "Could not check hyprsunset.service"
    readonly property string toggleError: "Job for hyprsunset.service failed: probe"

    property int step: 0
    property int waited: 0
    property int checks: 0
    property int failures: 0
    property bool done: false

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    function finish(): void {
        if (root.done) return
        root.done = true
        _ticks.stop()
        console.log("PROBE-NIGHTLIGHT " + (root.failures ? "failed " : "passed ") + root.checks + " checks")
    }

    // holds a step until its condition lands; a condition that never lands fails the run
    function ready(ok: bool, label: string, limit: int): bool {
        if (ok) {
            root.waited = 0
            return true
        }
        if (++root.waited > limit) {
            root.check(false, label)
            root.finish()
        }
        return false
    }

    function lines(file): var {
        file.reload()
        return file.text().split("\n").filter(l => l.length > 0)
    }
    function setFile(file, text: string): void {
        file.setText(text + "\n")
    }

    FileView { id: _systemctlCalls; path: root.base + "/systemctl-calls"; blockAllReads: true; printErrors: false }
    FileView { id: _unitState; path: root.base + "/unit-state"; blockAllReads: true; blockWrites: true; printErrors: false }
    FileView { id: _toggleMode; path: root.base + "/toggle-mode"; blockWrites: true; printErrors: false }

    Timer {
        id: _ticks
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            switch (root.step) {
            case 0:
                // the tool scan has to find the stand-in, and the first check has to land
                if (!root.ready(SystemTools.ready && NightLight.toolAvailable && NightLight.enabled,
                        "the stand-in tools are detected and the first check reads the unit active", 40))
                    return
                root.check(NightLight.lastError === "", "a check that answers leaves no error")

                NightLight._acceptCheckResult(true, -1)
                root.check(NightLight.lastError === root.checkError && NightLight.enabled,
                    "a timed-out check reports the error and leaves the state alone")
                NightLight._acceptCheckResult(false, 3)
                root.check(NightLight.lastError === "" && !NightLight.enabled,
                    "the next check that answers clears the check error and reads the unit off")
                NightLight._acceptCheckResult(false, 0)
                root.check(NightLight.lastError === "" && NightLight.enabled,
                    "a check that answers reads the unit on")

                root.setFile(_toggleMode, "fail")
                NightLight.toggle()
                root.check(!NightLight.enabled && NightLight.lastError === "",
                    "a toggle flips the row before systemctl answers")
                break
            case 1: {
                // the refused stop is followed by the check that puts the row back on
                const calls = root.lines(_systemctlCalls)
                if (!root.ready(calls.lastIndexOf("stop") >= 0
                        && calls.lastIndexOf("is-active") > calls.lastIndexOf("stop")
                        && NightLight.enabled && NightLight.lastError.length > 0,
                        "a refused stop reports its error and the check after it lands", 20))
                    return
                root.check(NightLight.lastError === root.toggleError,
                    "a toggle error survives the check that follows it")
                NightLight._acceptCheckResult(true, -1)
                root.check(NightLight.lastError === root.toggleError,
                    "a timed-out check does not replace a toggle error")
                NightLight._acceptCheckResult(false, 0)
                root.check(NightLight.lastError === root.toggleError,
                    "a check that answers does not clear a toggle error")

                root.setFile(_toggleMode, "ok")
                NightLight.toggle()
                root.check(NightLight.lastError === "" && !NightLight.enabled,
                    "the next toggle clears a toggle error")
                break
            }
            case 2:
                if (!root.ready(root.lines(_unitState)[0] === "inactive" && !NightLight.enabled,
                        "the stand-in unit stops on the next toggle", 20))
                    return
                root.check(NightLight.lastError === "", "a stop that succeeds leaves no error")
                root.finish()
                return
            }
            root.step++
        }
    }
}
