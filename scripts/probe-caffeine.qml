import QtQuick
import Quickshell
import Quickshell.Io
import "services"

// the stand-in systemctl, systemd-inhibit, systemd-run and dbus-monitor on PATH are the only
// commands Caffeine can reach; this probe steers the stand-in unit through files and reads back
// what it was asked
ShellRoot {
    id: root

    readonly property string base: Quickshell.env("SILERE_CAFFEINE_PROBE_ROOT")
    readonly property string checkError: "could not check hypr-shell-caffeine.service"
    readonly property string toggleError: "Job for hypr-shell-caffeine.service failed: probe"
    readonly property string idleInhibitor: "probe-who 1000 probe 4242 sleep idle probe-why block"

    property int step: 0
    property int waited: 0
    property int paused: 0
    property int checksBefore: 0
    property int stopsBefore: 0
    property int doneBefore: 0
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
        console.log("PROBE-CAFFEINE " + (root.failures ? "failed " : "passed ") + root.checks + " checks")
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
    function markCalls(): void {
        const calls = root.lines(_systemctlCalls)
        root.checksBefore = root.count(calls, "is-active")
        root.stopsBefore = root.count(calls, "stop")
        root.doneBefore = root.lines(_systemctlDone).length
    }

    // the drift and inhibitor polls sleep through idle, so their calls stay out of the counts
    Component.onCompleted: Idle.isIdle = true

    FileView { id: _systemctlCalls; path: root.base + "/systemctl-calls"; blockAllReads: true; printErrors: false }
    FileView { id: _systemctlDone; path: root.base + "/systemctl-done"; blockAllReads: true; printErrors: false }
    FileView { id: _unitState; path: root.base + "/unit-state"; blockAllReads: true; blockWrites: true; printErrors: false }
    FileView { id: _toggleMode; path: root.base + "/toggle-mode"; blockWrites: true; printErrors: false }
    FileView { id: _slowCheck; path: root.base + "/slow-check"; blockWrites: true; printErrors: false }
    FileView { id: _inhibitors; path: root.base + "/inhibitors"; blockWrites: true; printErrors: false }
    FileView { id: _inhibitDone; path: root.base + "/inhibit-done"; blockAllReads: true; printErrors: false }
    FileView { id: _slowInhibit; path: root.base + "/slow-inhibit"; blockWrites: true; printErrors: false }

    Timer {
        id: _ticks
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            switch (root.step) {
            case 0:
                // the settings name the unit, the tool scan has to find the stand-ins, and the
                // first check and inhibitor read have to land. Caffeine is first read once the
                // settings are in: a singleton made before then starts with no unit, and only the
                // tool scan finishing makes it check again, which may already have happened
                if (!root.ready(ShellSettings.ready && Caffeine.available && SystemTools.ready
                        && root.lines(_systemctlDone).length > 0 && root.lines(_inhibitDone).length > 0,
                        "the stand-in tools are detected and the first check reads the unit", 80))
                    return
                // a startup check queued behind the first may still be running
                if (++root.paused < 4) return
                root.paused = 0
                root.check(!Caffeine.manualActive && Caffeine.lastError === "",
                    "a check that answers reads the unit off and leaves no error")
                root.setFile(_slowCheck, "7")
                root.markCalls()
                Caffeine._checkActive()
                break
            case 1:
                if (!root.ready(Caffeine.lastError.length > 0, "a check that times out reports an error", 40))
                    return
                root.check(Caffeine.lastError === root.checkError && !Caffeine.manualActive,
                    "a timed-out check reports the error and leaves the state alone")
                root.check(root.lines(_systemctlDone).length === root.doneBefore,
                    "the stand-in's slow check was cut off at its deadline")
                // started outside the shell, so the next check reads it active
                root.setFile(_slowCheck, "0")
                root.setFile(_unitState, "active")
                root.markCalls()
                Caffeine._checkActive()
                break
            case 2:
                if (!root.ready(root.lines(_systemctlDone).length > root.doneBefore && Caffeine.manualActive,
                        "the next check reads the unit active", 20))
                    return
                root.check(Caffeine.lastError === "", "the next check that answers clears the check error")

                root.setFile(_toggleMode, "fail")
                root.markCalls()
                Caffeine.toggle()
                root.check(!Caffeine.manualActive && Caffeine.lastError === "",
                    "a toggle flips the row before systemctl answers")
                break
            case 3: {
                // the refused stop is followed by the check that puts the row back on
                const calls = root.lines(_systemctlCalls)
                if (!root.ready(root.count(calls, "stop") > root.stopsBefore
                        && calls.lastIndexOf("is-active") > calls.lastIndexOf("stop")
                        && root.lines(_systemctlDone).length > root.doneBefore
                        && Caffeine.manualActive && Caffeine.lastError.length > 0,
                        "a refused stop reports its error and the check after it lands", 20))
                    return
                root.check(Caffeine.lastError === root.toggleError,
                    "a toggle error survives the check that follows it")
                root.setFile(_slowCheck, "7")
                root.markCalls()
                Caffeine._checkActive()
                break
            }
            case 4:
                // the check runs into its own deadline
                if (++root.paused < 26) return
                root.paused = 0
                root.check(root.count(root.lines(_systemctlCalls), "is-active") === root.checksBefore + 1
                        && root.lines(_systemctlDone).length === root.doneBefore,
                    "the slow check after the toggle error was cut off at its deadline")
                root.check(Caffeine.lastError === root.toggleError && Caffeine.manualActive,
                    "a check that times out does not replace a toggle error")

                root.setFile(_slowCheck, "0")
                root.setFile(_toggleMode, "ok")
                root.markCalls()
                Caffeine.toggle()
                root.check(Caffeine.lastError === "" && !Caffeine.manualActive,
                    "the next toggle clears a toggle error")
                break
            case 5: {
                const calls = root.lines(_systemctlCalls)
                if (!root.ready(root.count(calls, "stop") > root.stopsBefore
                        && calls.lastIndexOf("is-active") > calls.lastIndexOf("stop")
                        && root.lines(_systemctlDone).length > root.doneBefore
                        && root.lines(_unitState)[0] === "inactive" && !Caffeine.manualActive,
                        "the next toggle stops the unit and the check after it lands", 20))
                    return
                root.check(Caffeine.lastError === "", "a stop that succeeds leaves no error")

                // started outside the shell; the first check runs into its deadline and the
                // second, asked for while the first runs, answers from its exit
                root.setFile(_unitState, "active")
                root.setFile(_slowCheck, "7")
                root.markCalls()
                Caffeine._checkActive()
                break
            }
            case 6:
                // the stand-in reads the delay before the next one is written
                if (++root.paused < 2) return
                root.paused = 0
                root.setFile(_slowCheck, "0")
                Caffeine._checkActive()
                root.check(Caffeine._recheckPending, "a check asked for while one runs queues behind it")
                break
            case 7:
                if (!root.ready(root.lines(_systemctlDone).length > root.doneBefore,
                        "the check queued behind a timed-out one answers", 40))
                    return
                // the answer lands from the stand-in's exit, a moment after its line
                if (++root.paused < 2) return
                root.paused = 0
                root.check(root.count(root.lines(_systemctlCalls), "is-active") === root.checksBefore + 2,
                    "the timed-out check and the one queued behind it both reach the stand-in")
                root.check(Caffeine.manualActive,
                    "a check queued behind a timed-out one is not judged timed out")
                root.check(Caffeine.lastError === "",
                    "a check queued behind a timed-out one clears its error")

                // stopped outside the shell; two slow checks that each answer inside their own deadline
                root.setFile(_unitState, "inactive")
                root.setFile(_slowCheck, "3.2")
                root.markCalls()
                Caffeine._checkActive()
                break
            case 8:
                if (++root.paused < 2) return
                root.paused = 0
                Caffeine._checkActive()
                root.check(Caffeine._recheckPending, "a second slow check queues behind the first")
                break
            case 9: {
                const done = root.lines(_systemctlDone).slice(root.doneBefore)
                if (!root.ready(done.length >= 2 || Caffeine.lastError.length > 0,
                        "a check started from the last one's exit answers", 40))
                    return
                root.check(done.length === 2 && root.count(done, "is-active 3.2") === 2
                        && Caffeine.lastError === "" && !Caffeine.manualActive,
                    "a check that follows a slow one gets a deadline of its own")

                // the same for the inhibitor list: a slow read with a second queued behind it,
                // which finds an idle inhibitor the first did not
                root.doneBefore = root.lines(_inhibitDone).length
                root.setFile(_slowInhibit, "3.2")
                Caffeine._checkInhibitors()
                break
            }
            case 10:
                if (++root.paused < 2) return
                root.paused = 0
                root.setFile(_inhibitors, root.idleInhibitor)
                Caffeine._checkInhibitors()
                root.check(Caffeine._inhibitCheckPending, "an inhibitor read asked for while one runs queues behind it")
                break
            case 11:
                // both reads take 3.2s; past that the second was cut off
                if (root.lines(_inhibitDone).length < root.doneBefore + 2 && ++root.paused < 32) return
                root.paused = 0
                break
            case 12: {
                // the answer lands from the stand-in's exit, a moment after its line
                if (++root.paused < 2) return
                root.paused = 0
                const done = root.lines(_inhibitDone).slice(root.doneBefore)
                root.check(done.length === 2 && root.count(done, "list 3.2") === 2
                        && Caffeine.inhibited && Caffeine.inhibitorLabel === "probe-who",
                    "an inhibitor read that follows a slow one gets a deadline of its own")
                root.finish()
                return
            }
            }
            root.step++
        }
    }
}
