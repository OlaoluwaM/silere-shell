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
    property int paused: 0
    property int startsBefore: 0
    property int stopsBefore: 0
    property int pushesBefore: 0
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
    function count(list, word: string): int {
        return list.filter(l => l === word).length
    }
    // the stand-in has answered the latest toggle once a check follows its call
    function settled(): bool {
        const calls = root.lines(_systemctlCalls)
        const last = Math.max(calls.lastIndexOf("start"), calls.lastIndexOf("stop"))
        return calls.lastIndexOf("is-active") > last
    }
    function markCalls(): void {
        const calls = root.lines(_systemctlCalls)
        root.startsBefore = root.count(calls, "start")
        root.stopsBefore = root.count(calls, "stop")
    }
    function toggledOnce(word: string): bool {
        const calls = root.lines(_systemctlCalls)
        const starts = root.count(calls, "start") - root.startsBefore
        const stops = root.count(calls, "stop") - root.stopsBefore
        return word === "start" ? starts === 1 && stops === 0 : stops === 1 && starts === 0
    }

    FileView { id: _systemctlCalls; path: root.base + "/systemctl-calls"; blockAllReads: true; printErrors: false }
    FileView { id: _unitState; path: root.base + "/unit-state"; blockAllReads: true; blockWrites: true; printErrors: false }
    FileView { id: _toggleMode; path: root.base + "/toggle-mode"; blockWrites: true; printErrors: false }
    FileView { id: _hyprctlCalls; path: root.base + "/hyprctl-calls"; blockAllReads: true; printErrors: false }
    FileView { id: _hyprctlOverlap; path: root.base + "/hyprctl-overlap"; blockAllReads: true; printErrors: false }
    FileView { id: _slowCheck; path: root.base + "/slow-check"; blockWrites: true; printErrors: false }

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
                root.check(!ControlSurfaces.anyOpen && !NightLight._watched,
                    "with every control surface shut the drift poll is off")

                // started outside the shell while nothing showed it
                root.setFile(_unitState, "active")
                QuickActionsState.open = true
                root.check(QuickActionsState.open && NightLight._watched,
                    "an open control surface turns the drift poll on")
                break
            case 3: {
                if (!root.ready(NightLight.enabled, "opening a control surface checks the unit", 20))
                    return
                QuickActionsState.close()
                // stopped outside the shell, so `enabled` is stale with every surface shut
                root.setFile(_unitState, "inactive")
                root.markCalls()
                root.check(!NightLight._watched && NightLight.enabled,
                    "with every surface shut the row keeps its stale state")
                root.check(NightLight.toggleFresh() === "queued",
                    "a keybind toggle with every surface shut waits on a fresh check")
                root.check(NightLight.toggleFresh() === "busy",
                    "a second keybind toggle before the first settles is refused")
                root.check(QuickActionsState._nightLightReply()
                        === "error: a night light change is already in progress",
                    "the keybind reply names a queued toggle as one in progress")
                break
            }
            case 4:
                if (!root.ready(root.settled() && NightLight.enabled
                        && root.lines(_unitState)[0] === "active",
                        "the queued toggle starts the unit the fresh check found stopped", 20))
                    return
                root.check(root.toggledOnce("start"),
                    "the queued toggle sends one start and no stop")

                QuickActionsState.open = true
                root.markCalls()
                root.check(NightLight.toggleFresh() === "" && !NightLight.enabled,
                    "with a control surface open a keybind toggle acts at once")
                break
            case 5:
                if (!root.ready(root.settled() && !NightLight.enabled
                        && root.lines(_unitState)[0] === "inactive",
                        "the immediate toggle stops the unit", 20))
                    return
                root.check(root.toggledOnce("stop"), "the immediate toggle sends one stop")
                QuickActionsState.close()

                // a check that has already read the unit when the keybind comes
                root.setFile(_slowCheck, "1")
                root.setFile(_unitState, "active")
                QuickActionsState.open = true
                QuickActionsState.close()
                break
            case 6:
                // the stand-in reads the unit before its slow answer
                if (++root.paused < 2) return
                root.paused = 0
                root.setFile(_unitState, "inactive")
                root.markCalls()
                root.check(NightLight.toggleFresh() === "queued",
                    "a keybind toggle during a check queues behind it")
                break
            case 7:
                if (!root.ready(root.settled() && NightLight.enabled
                        && root.lines(_unitState)[0] === "active",
                        "the toggle waits for the check that follows the request", 40))
                    return
                root.check(root.toggledOnce("start"),
                    "a check already running when the keybind came does not decide its toggle")
                break
            case 8:
                // the check after the start is still on its slow answer
                if (++root.paused < 8) return
                root.paused = 0
                root.setFile(_slowCheck, "7")
                root.setFile(_unitState, "inactive")
                root.markCalls()
                root.check(NightLight.toggleFresh() === "queued",
                    "a keybind toggle queues behind a check that will time out")
                break
            case 9:
                if (!root.ready(NightLight.lastError === root.checkError,
                        "a check that times out reports its error", 40))
                    return
                break
            case 10:
                if (++root.paused < 4) return
                root.paused = 0
                root.check(root.count(root.lines(_systemctlCalls), "start") === root.startsBefore
                        && root.count(root.lines(_systemctlCalls), "stop") === root.stopsBefore,
                    "a check that times out drops the queued toggle")
                root.setFile(_slowCheck, "0")
                root.check(NightLight.toggleFresh() === "queued",
                    "a dropped toggle leaves the next keybind free to queue")
                break
            case 11:
                if (!root.ready(root.settled() && NightLight.enabled
                        && root.lines(_unitState)[0] === "active" && NightLight.lastError === "",
                        "the next keybind toggle starts the unit and clears the check error", 20))
                    return
                root.check(root.toggledOnce("start"), "the next keybind toggle sends one start")
                break
            case 12: {
                // the start's confirm push answers first
                if (++root.paused < 4) return
                root.paused = 0
                ShellSettings.nightLightAuto = false
                root.pushesBefore = root.lines(_hyprctlCalls).length
                // one burst the way a slider sweep commits it, ending below 6500 so the
                // final push names its temperature rather than the identity matrix
                for (let t = 4000; t <= 5900; t += 100) ShellSettings.nightLightTemp = t
                ShellSettings.nightLightTemp = 3700
                break
            }
            case 13: {
                const pushes = root.lines(_hyprctlCalls).slice(root.pushesBefore)
                if (!root.ready(pushes.length > 0 && pushes[pushes.length - 1] === "temperature 3700",
                        "a burst of temperature changes ends on its final value", 20))
                    return
                // the burst runs in one turn: its first value starts the one push in flight and
                // every later one only replaces the value waiting behind it, so two calls carry
                // all 21 values
                root.check(pushes.length === 2 && pushes[0] === "temperature 4000",
                    "a burst of 21 temperatures reaches hyprctl as its first and last value only")
                root.check(root.lines(_hyprctlOverlap).length === 0,
                    "no temperature push starts while another is running")
                break
            }
            case 14: {
                // the burst's last push is still running when its line lands
                if (++root.paused < 3) return
                root.paused = 0
                root.pushesBefore = root.lines(_hyprctlCalls).length
                ShellSettings.nightLightTemp = 4400
                ShellSettings.nightLightTemp = 4500
                // turned off while 4500 waits behind 4400
                NightLight.toggle()
                ShellSettings.nightLightTemp = 4600
                ShellSettings.nightLightTemp = 4700
                break
            }
            case 15: {
                if (++root.paused < 6) return
                if (!root.ready(root.settled() && !NightLight.enabled,
                        "the unit stops under the pending push", 20))
                    return
                const pushes = root.lines(_hyprctlCalls).slice(root.pushesBefore)
                root.check(pushes.length === 1 && pushes[0] === "temperature 4400",
                    "turning night light off drops the waiting push and sends nothing while off")

                // a slider move right after a start: the start's confirm push lands while the
                // move's push is still running
                root.pushesBefore = root.lines(_hyprctlCalls).length
                NightLight.toggle()
                ShellSettings.nightLightTemp = 4100
                break
            }
            case 16: {
                const pushes = root.lines(_hyprctlCalls).slice(root.pushesBefore)
                if (!root.ready(pushes.length === 2 && root.settled() && NightLight.enabled,
                        "the start's confirm push follows the slider's push", 20))
                    return
                root.check(pushes[0] === "temperature 4100" && pushes[1] === "temperature 4100",
                    "the confirm push sends the temperature the slider left")
                root.check(root.lines(_hyprctlOverlap).length === 0,
                    "the confirm push waits for a slider push in flight")
                root.finish()
                return
            }
            }
            root.step++
        }
    }
}
