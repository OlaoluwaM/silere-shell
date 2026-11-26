import QtQuick
import Quickshell
import Quickshell.Io
import "services"

// the stand-in systemctl, sunsetr and timedatectl on PATH are the only commands NightLight can
// reach; this probe steers them through files and reads back what they were asked
ShellRoot {
    id: root

    readonly property string base: Quickshell.env("SILERE_NIGHTLIGHT_PROBE_ROOT")
    readonly property string checkError: "Could not check sunsetr.service"
    readonly property string toggleError: "Job for sunsetr.service failed: probe"

    property int step: 0
    property int waited: 0
    property int paused: 0
    property int startsBefore: 0
    property int stopsBefore: 0
    property int doneBefore: 0
    property int checksBefore: 0
    property int runsBefore: 0
    property int getsBefore: 0
    property int setsBefore: 0
    property int modeIndex: 0
    property int modeStep: 0
    property real latBefore: NaN
    // every night temperature the service showed, so a value restored for a moment is seen
    property var tempHistory: []
    property string feedText: ""
    // the stand-in deletes the file it exits on, which the view never sees, so each request differs
    property int exits: 0
    property int checks: 0
    property int failures: 0
    property bool done: false
    readonly property var clockModes: ["start_at", "center", "finish_by"]

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
    function checkCount(): int {
        return root.count(root.lines(_systemctlCalls), "is-active")
    }
    function newSets(): var {
        return root.lines(_setCalls).slice(root.setsBefore)
    }

    // a follow line the stand-in prints next; it reads the feed by line count
    function feed(line: string): void {
        root.feedText += line + "\n"
        _statusFeed.setText(root.feedText)
    }
    // sunsetr stamps local time to the nanosecond with the zone's offset
    function stamp(h: int, m: int): string {
        const d = new Date()
        d.setHours(h, m, 0, 0)
        const pad = n => (n < 10 ? "0" : "") + n
        const off = -d.getTimezoneOffset()
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
            + "T" + pad(h) + ":" + pad(m) + ":00.000679991"
            + (off >= 0 ? "+" : "-") + pad(Math.floor(Math.abs(off) / 60)) + ":" + pad(Math.abs(off) % 60)
    }
    function state(fields: var): string {
        return JSON.stringify(Object.assign({ event_type: "state_applied", active_preset: "default",
            current_gamma: 100.0 }, fields))
    }
    function config(mode: string, temp: string, sunset: string): void {
        root.setFile(_sunsetrConf, ["transition_mode=" + mode, "night_temp=" + temp, "sunset=" + sunset,
            "sunrise=06:00:00", "latitude=41.9", "longitude=-87.7"].join("\n"))
    }

    FileView { id: _systemctlCalls; path: root.base + "/systemctl-calls"; blockAllReads: true; printErrors: false }
    FileView { id: _unitState; path: root.base + "/unit-state"; blockAllReads: true; blockWrites: true; printErrors: false }
    FileView { id: _toggleMode; path: root.base + "/toggle-mode"; blockWrites: true; printErrors: false }
    FileView { id: _slowCheck; path: root.base + "/slow-check"; blockWrites: true; printErrors: false }
    FileView { id: _systemctlDone; path: root.base + "/systemctl-done"; blockAllReads: true; printErrors: false }
    FileView { id: _statusInitial; path: root.base + "/status-initial"; blockWrites: true; printErrors: false }
    FileView { id: _statusFeed; path: root.base + "/status-feed"; blockWrites: true; printErrors: false }
    FileView { id: _statusExit; path: root.base + "/status-exit"; blockWrites: true; printErrors: false }
    FileView { id: _statusRuns; path: root.base + "/status-runs"; blockAllReads: true; printErrors: false }
    FileView { id: _sunsetrConf; path: root.base + "/sunsetr.conf"; blockWrites: true; printErrors: false }
    FileView { id: _getMode; path: root.base + "/get-mode"; blockWrites: true; printErrors: false }
    FileView { id: _getCalls; path: root.base + "/get-calls"; blockAllReads: true; printErrors: false }
    FileView { id: _setMode; path: root.base + "/set-mode"; blockWrites: true; printErrors: false }
    FileView { id: _slowSet; path: root.base + "/slow-set"; blockWrites: true; printErrors: false }
    FileView { id: _setCalls; path: root.base + "/set-calls"; blockAllReads: true; printErrors: false }
    FileView { id: _setDone; path: root.base + "/set-done"; blockAllReads: true; printErrors: false }
    FileView { id: _setOverlap; path: root.base + "/set-overlap"; blockAllReads: true; printErrors: false }
    FileView { id: _getDuringSet; path: root.base + "/get-during-set"; blockAllReads: true; printErrors: false }
    FileView { id: _slowGet; path: root.base + "/slow-get"; blockWrites: true; printErrors: false }
    FileView { id: _statusDown; path: root.base + "/status-down"; blockWrites: true; printErrors: false }
    FileView { id: _tzZone; path: root.base + "/tz-zone"; blockWrites: true; printErrors: false }
    FileView { id: _slowTz; path: root.base + "/slow-tz"; blockWrites: true; printErrors: false }
    Connections {
        target: NightLight
        function onNightTempChanged() { root.tempHistory = root.tempHistory.concat([NightLight.nightTemp]) }
    }
    // moves the stand-in sunsetr out of PATH and back, so the tool scan loses and finds it
    Process { id: _moveSunsetr }

    Component.onCompleted: {
        ShellSettings.clock12h = false
        root.setFile(_statusInitial, root.state({ period: "day", state: "stable", current_temp: 6500,
            next_period: root.stamp(16, 20) }))
    }

    Timer {
        id: _ticks
        interval: 250
        running: true
        repeat: true
        onTriggered: {
            switch (root.step) {
            case 0:
                // the tool scan has to find the stand-ins, the first check has to land, and the
                // follow it starts has to print its first state
                if (!root.ready(SystemTools.ready && NightLight.available && NightLight.enabled
                        && NightLight.live && NightLight.configKnown,
                        "the stand-in tools are detected, the first check reads the unit active, "
                        + "the follow connects and the config is read", 40))
                    return
                root.check(NightLight.period === "day" && NightLight.currentTemp === 6500
                        && !NightLight.transitioning && NightLight.targetTemp === 0,
                    "the first state the follow prints sets the period and temperature")
                root.check(NightLight.statusLabel === "Neutral"
                        && NightLight.detailLabel === "Neutral until 16:20",
                    "a stable day reads Neutral and, in the card, the time it ends")
                // get prints every value as a string
                root.check(NightLight.nightTemp === 3300 && typeof NightLight.nightTemp === "number"
                        && NightLight.schedule === "sun" && NightLight.clockSunsetMin === 19 * 60
                        && NightLight.clockSunriseMin === 6 * 60
                        && Math.abs(NightLight.configLatitude - 41.9) < 0.0001
                        && Math.abs(NightLight.configLongitude + 87.7) < 0.0001,
                    "the config read turns get's strings into numbers, minutes and a schedule")
                root.check(Math.abs(NightLight._useLat - 41.9) < 0.0001 && Math.abs(NightLight._useLon + 87.7) < 0.0001,
                    "the sun maths use sunsetr's coordinates once the config is known")
                root.check(!isNaN(NightLight.eveningFadeStartHour) && !isNaN(NightLight.morningFadeEndHour),
                    "following the sun gives the arc its fade windows")
                root.check(root.lines(_setCalls).length === 0,
                    "an ordinary start writes nothing to sunsetr's config")

                root.feed(root.state({ period: "sunset", state: "transitioning", progress: 0.4,
                    current_temp: 4500, target_temp: 2500, target_gamma: 90.0, next_period: root.stamp(16, 55) }))
                break
            case 1: {
                if (!root.ready(NightLight.transitioning, "a transitioning state lands", 20))
                    return
                const at = NightLight.nextPeriodAt
                root.check(NightLight.targetTemp === 2500
                        && at instanceof Date && at.getHours() === 16 && at.getMinutes() === 55,
                    "a transitioning state sets the target and when the period ends")
                root.check(NightLight.statusLabel === "4500K"
                        && NightLight.detailLabel === "4500K → 2500K by 16:55",
                    "a fade to night reads its temperature and, in the card, the target with its end")
                root.feed(JSON.stringify({ event_type: "period_changed", from_period: "sunset", to_period: "night" }))
                root.feed(root.state({ period: "sunrise", state: "transitioning", progress: 0.1,
                    current_temp: 2800, target_temp: 6500, target_gamma: 100.0, next_period: root.stamp(7, 35) }))
                break
            }
            case 2:
                if (!root.ready(NightLight.period === "sunrise", "a fade to day lands", 20))
                    return
                root.check(NightLight.detailLabel === "2800K → neutral by 07:35",
                    "a fade to 6500K reads as a fade to neutral")
                root.feed(root.state({ period: "night", state: "stable", current_temp: 2500,
                    next_period: root.stamp(15, 42) }))
                break
            case 3:
                if (!root.ready(NightLight.period === "night", "a stable night lands", 20))
                    return
                root.check(NightLight.statusLabel === "2500K"
                        && NightLight.detailLabel === "2500K until 15:42" && NightLight.targetTemp === 0
                        && !NightLight.transitioning,
                    "a stable night reads its temperature and when it ends, with no target")
                // what the follow prints with no daemon, then lines that are not whole events
                root.feed("[ERROR] No sunsetr process is running")
                root.feed("Start sunsetr first, then run this command again")
                root.feed("{\"event_type\":\"state_applied\",\"period\":\"da")
                root.feed("{\"event_type\":\"bogus\",\"period\":\"day\"}")
                root.feed("{}")
                root.feed("[\"state_applied\"]")
                break
            case 4:
                // the stand-in prints a fresh feed line every twentieth of a second
                if (++root.paused < 4) return
                root.paused = 0
                root.check(NightLight.live && NightLight.period === "night" && NightLight.currentTemp === 2500,
                    "plain text, a truncated line and unknown events leave the state alone")
                root.feed(root.state({ period: "day", state: "stable", current_temp: 5000,
                    next_period: root.stamp(16, 20) }))
                break
            case 5:
                if (!root.ready(NightLight.period === "day", "a warm day lands", 20))
                    return
                root.check(NightLight.statusLabel === "5000K" && NightLight.period === "day",
                    "a day warmer than 6500K reads its temperature, not Neutral")
                root.feed(root.state({ period: "static", state: "static", current_temp: 6500 }))
                break
            case 6:
                if (!root.ready(NightLight.period === "static", "a static state at 6500K lands", 20))
                    return
                root.check(NightLight.statusLabel === "Neutral",
                    "6500K reads Neutral whichever period the daemon is in")
                root.feed(root.state({ period: "static", state: "static", current_temp: 4000 }))
                break
            case 7:
                if (!root.ready(NightLight.currentTemp === 4000, "a static state after the skipped lines lands", 20))
                    return
                root.check(NightLight.period === "static" && NightLight.detailLabel === "4000K"
                        && NightLight.nextPeriodAt === null && NightLight.statusLabel === "4000K",
                    "a static state reads its temperature with no end")
                // the daemon announces an edit made outside the shell
                root.getsBefore = root.lines(_getCalls).length
                root.config("geo", "3400", "19:00:00")
                root.feed(JSON.stringify({ event_type: "config_changed", target_period: "day",
                    target_temp: 6500, target_gamma: 100.0 }))
                break
            case 8:
                if (!root.ready(NightLight.nightTemp === 3400 && root.lines(_getCalls).length > root.getsBefore,
                        "a config_changed event reads the config again", 20))
                    return
                root.getsBefore = root.lines(_getCalls).length
                root.config("geo", "3300", "19:00:00")
                root.feed(JSON.stringify({ event_type: "preset_changed", from_preset: "default",
                    to_preset: "evening", target_period: "night", target_temp: 3300, target_gamma: 100.0 }))
                break
            case 9:
                if (!root.ready(NightLight.nightTemp === 3300 && root.lines(_getCalls).length > root.getsBefore,
                        "a preset_changed event reads the config again", 20))
                    return
                // the daemon stops its stream while the unit stays up
                root.checksBefore = root.checkCount()
                root.runsBefore = root.lines(_statusRuns).length
                root.setFile(_statusExit, String(++root.exits))
                break
            case 10:
                if (!root.ready(!NightLight.live && root.checkCount() > root.checksBefore,
                        "the follow exiting while on runs a check", 20))
                    return
                root.check(NightLight.enabled, "a check after the follow exits keeps an active unit on")
                break
            case 11:
                if (!root.ready(NightLight.live && root.lines(_statusRuns).length > root.runsBefore,
                        "with the unit still active the follow restarts and connects", 40))
                    return
                root.check(NightLight.period === "day" && NightLight.currentTemp === 6500,
                    "the restarted follow takes the state it prints on connecting")
                // the unit stopped outside the shell, and its follow ends with it
                root.setFile(_unitState, "inactive")
                root.runsBefore = root.lines(_statusRuns).length
                root.setFile(_statusExit, String(++root.exits))
                break
            case 12:
                if (!root.ready(!NightLight.enabled, "the check after the follow exits finds the unit stopped", 20))
                    return
                root.check(!NightLight.live && NightLight.period === "" && NightLight.currentTemp === 0
                        && NightLight.targetTemp === 0 && !NightLight.transitioning
                        && NightLight.nextPeriodAt === null,
                    "turning off clears the live state")
                root.check(NightLight.statusLabel === NightLight.offStatus
                        && NightLight.detailLabel === "Off",
                    "turned off, the labels read the off status and Off")
                // a line the parser still held when the reader was stopped
                NightLight._acceptStatusLine(root.state({ period: "day", state: "stable", current_temp: 6500 }))
                root.check(!NightLight.live && NightLight.period === "" && NightLight.currentTemp === 0,
                    "a status line read while off changes nothing")
                // the daemon writes its config on its first start, so until then reads fail
                root.setFile(_getMode, "fail")
                NightLight._readConfig()
                break
            case 13:
                // a restart would land within the reader's first backoff
                if (++root.paused < 8) return
                root.paused = 0
                root.check(root.lines(_statusRuns).length === root.runsBefore,
                    "the follow stays down while the unit is off")
                root.check(!NightLight.configKnown, "a read before the daemon's first start leaves the config unknown")
                root.setFile(_getMode, "ok")
                root.getsBefore = root.lines(_getCalls).length
                root.setFile(_toggleMode, "ok")
                NightLight.toggle()
                break
            case 14:
                if (!root.ready(root.settled() && NightLight.enabled && NightLight.live,
                        "a toggle on starts the unit and the follow connects again", 40))
                    return
                break
            case 15:
                if (!root.ready(NightLight.configKnown && root.lines(_getCalls).length > root.getsBefore,
                        "the first state after connecting reads a config that was unknown", 20))
                    return

                // a follow that never connects says nothing about the unit, so it checks nothing
                root.setFile(_statusDown, "1")
                root.checksBefore = root.checkCount()
                root.setFile(_statusExit, String(++root.exits))
                break
            case 16:
                if (!root.ready(!NightLight.live && root.checkCount() > root.checksBefore,
                        "a lost stream runs one check", 20))
                    return
                // the check's answer lands before counting starts
                if (++root.paused < 2) return
                root.paused = 0
                root.checksBefore = root.checkCount()
                root.runsBefore = root.lines(_statusRuns).length
                break
            case 17:
                // two restarts land within the reader's first backoffs, one and two seconds
                if (++root.paused < 22) return
                root.paused = 0
                root.check(root.lines(_statusRuns).length >= root.runsBefore + 2,
                    "a follow that finds no daemon keeps restarting")
                root.check(root.checkCount() === root.checksBefore && NightLight.enabled,
                    "a follow that exits before any state runs no check")
                root.setFile(_statusDown, "0")
                break
            case 18:
                if (!root.ready(NightLight.live, "the follow connects once the daemon answers", 48))
                    return
                NightLight.toggle()
                break
            case 19:
                if (!root.ready(root.settled() && !NightLight.enabled, "the unit stops before the slow start", 20))
                    return
                // a start that answers late: the follow comes up and is lost while it runs
                root.setFile(_toggleMode, "slow")
                root.markCalls()
                NightLight.toggle()
                break
            case 20:
                if (!root.ready(NightLight.live, "the follow connects while the slow start runs", 8))
                    return
                root.setFile(_statusExit, String(++root.exits))
                break
            case 21: {
                if (!root.ready(!NightLight.live, "the follow is lost while the slow start runs", 8))
                    return
                const calls = root.lines(_systemctlCalls)
                root.check(root.lines(_unitState)[0] === "inactive",
                    "the slow start is still running when the follow is lost")
                root.check(calls.lastIndexOf("is-active") < calls.lastIndexOf("start"),
                    "a stream lost while a toggle runs leaves the check to the toggle")
                break
            }
            case 22:
                if (!root.ready(root.settled() && NightLight.enabled && NightLight.live,
                        "the slow start lands and the follow connects", 40))
                    return
                root.setFile(_toggleMode, "ok")

                // every clock mode reads as a clock schedule
                root.modeIndex = 0
                break
            case 23:
                root.modeStep = root.step
                root.getsBefore = root.lines(_getCalls).length
                root.config(root.clockModes[root.modeIndex], "3300", "18:30:45")
                NightLight._readConfig()
                break
            case 24: {
                const mode = root.clockModes[root.modeIndex]
                if (!root.ready(root.lines(_getCalls).length > root.getsBefore && NightLight._mode === mode,
                        "a read of a " + mode + " config lands", 20))
                    return
                root.check(NightLight.schedule === "clock" && NightLight.clockSunsetMin === 18 * 60 + 30,
                    "transition mode " + mode + " reads as a clock schedule")
                root.check(isNaN(NightLight.eveningFadeStartHour) && isNaN(NightLight.morningFadeEndHour),
                    "a clock schedule has no sun fade windows")
                if (++root.modeIndex < root.clockModes.length) {
                    root.step = root.modeStep
                    return
                }
                // the last mode read was finish_by
                root.setsBefore = root.lines(_setCalls).length
                NightLight.setSchedule("clock")
                root.check(NightLight.schedule === "clock" && NightLight._mode === "finish_by",
                    "asking for a clock schedule keeps the clock mode already set")
                break
            }
            case 25:
                if (++root.paused < 3) return
                root.paused = 0
                root.check(root.newSets().length === 0,
                    "asking for a clock schedule with one already set writes nothing")
                // a static config holds no night temperature, clock times or coordinates
                root.getsBefore = root.lines(_getCalls).length
                root.setFile(_sunsetrConf, "transition_mode=static\nstatic_temp=4500\nstatic_gamma=100")
                NightLight._readConfig()
                break
            case 26:
                if (!root.ready(NightLight._mode === "static", "a read of a static config lands", 20))
                    return
                root.check(NightLight.configKnown && NightLight.schedule === "fixed",
                    "a config with no coordinates or clock times is known, and static reads as fixed")
                root.check(NightLight.nightTemp === 3300 && NightLight.clockSunsetMin === 18 * 60 + 30
                        && Math.abs(NightLight.configLatitude - 41.9) < 0.0001,
                    "fields a config leaves out keep their last values")
                root.check(isNaN(NightLight.eveningFadeStartHour), "a fixed schedule has no sun fade windows")
                root.setsBefore = root.lines(_setCalls).length
                NightLight.setSchedule("clock")
                root.check(NightLight.schedule === "clock", "asking for a clock schedule from fixed shows at once")
                break
            case 27:
                if (!root.ready(root.newSets().length === 1 && NightLight._mode === "start_at"
                        && root.lines(_setDone).length >= root.setsBefore + 1,
                        "a clock schedule from fixed is written", 20))
                    return
                root.check(root.newSets()[0] === "transition_mode=start_at",
                    "a clock schedule from fixed writes start_at")
                break
            case 28:
                if (++root.paused < 2) return
                root.paused = 0

                // a slider sweep: one write runs, the rest wait and coalesce by field
                root.setFile(_slowSet, "0.6")
                root.setsBefore = root.lines(_setCalls).length
                root.getsBefore = root.lines(_getCalls).length
                NightLight.setNightTemp(3000)
                NightLight.setNightTemp(3100)
                NightLight.setClockSunset(18 * 60 + 30)
                NightLight.setNightTemp(3200)
                root.check(NightLight.nightTemp === 3200 && NightLight.clockSunsetMin === 18 * 60 + 30,
                    "a write shows its value at once")
                break
            case 29:
                if (!root.ready(root.newSets().length >= 1, "the sweep's first write starts", 8))
                    return
                // a surface opening mid-sweep asks for a read, which waits for the writes
                NightLight._readConfig()
                break
            case 30: {
                const sets = root.newSets()
                if (!root.ready(sets.length >= 2 && root.lines(_setDone).length >= root.setsBefore + 2
                        && root.lines(_getCalls).length > root.getsBefore,
                        "a sweep's writes finish and the config is read back", 20))
                    return
                root.check(sets.length === 2 && sets[0] === "night_temp=3000"
                        && sets[1] === "night_temp=3200 sunset=18:30:00",
                    "a sweep reaches sunsetr as its first value and then the last of each field")
                root.check(root.lines(_setOverlap).length === 0, "no write starts while another is running")
                root.check(root.lines(_getDuringSet).length === 0, "no read runs while a write is running")
                break
            }
            case 31:
                if (!root.ready(NightLight.configKnown && NightLight.nightTemp === 3200,
                        "the read after the writes keeps the last value", 20))
                    return
                // a refused write: the read that follows restores the config's value
                root.setFile(_slowSet, "0.1")
                root.setFile(_setMode, "fail")
                root.setsBefore = root.lines(_setCalls).length
                root.getsBefore = root.lines(_getCalls).length
                NightLight.setNightTemp(2000)
                root.check(NightLight.nightTemp === 2000, "a write shows its value before sunsetr answers")
                break
            case 32:
                if (!root.ready(root.newSets().length === 1 && root.lines(_getCalls).length > root.getsBefore
                        && NightLight.nightTemp === 3200,
                        "a refused write is followed by a read that restores the value", 20))
                    return
                root.check(root.newSets()[0] === "night_temp=2000" && NightLight.configKnown,
                    "the refused write carried its value and the read after it is known")
                root.setFile(_setMode, "ok")

                // a slow read reads the file, then a fast write starts and finishes before it answers
                root.setFile(_slowGet, "1")
                root.getsBefore = root.lines(_getCalls).length
                NightLight._readConfig()
                break
            case 33:
                // the stand-in reads the file before its delay
                if (++root.paused < 2) return
                root.paused = 0
                root.tempHistory = []
                NightLight.setNightTemp(3700)
                break
            case 34:
                if (!root.ready(root.lines(_getCalls).length >= root.getsBefore + 2,
                        "the read after the write follows the slow one", 20))
                    return
                // and answers
                if (++root.paused < 6) return
                root.paused = 0
                root.check(NightLight.nightTemp === 3700 && root.tempHistory.indexOf(3200) < 0,
                    "a read that began before the latest write never shows the old value")
                root.setFile(_slowGet, "0")
                break
            case 35:
                // a read that fails leaves the values and says they are unknown
                root.setFile(_getMode, "fail")
                root.setsBefore = root.lines(_setCalls).length
                root.getsBefore = root.lines(_getCalls).length
                NightLight._readConfig()
                break
            case 36:
                if (!root.ready(!NightLight.configKnown, "a failed read marks the config unknown", 20))
                    return
                root.check(NightLight.nightTemp === 3700 && NightLight.schedule === "clock",
                    "a failed read keeps the last values")
                root.check(Math.abs(NightLight._useLat - NightLight._autoLat) < 0.0001
                        || (!NightLight._geoResolved && NightLight._useLat === 45),
                    "with the config unknown the sun maths fall back to the zone table")
                root.setFile(_getMode, "garbage")
                NightLight.setSchedule("sun")
                root.check(NightLight.schedule === "sun", "asking for the sun shows at once")
                break
            case 37: {
                if (!root.ready(root.newSets().length === 1 && root.lines(_getCalls).length >= root.getsBefore + 2,
                        "the schedule write and its read back run", 20))
                    return
                root.check(root.newSets()[0] === "transition_mode=geo", "asking for the sun writes geo")
                break
            }
            case 38:
                if (++root.paused < 2) return
                root.paused = 0
                root.check(!NightLight.configKnown, "a read that prints no JSON leaves the config unknown")
                root.check(NightLight.schedule === "sun" && isNaN(NightLight.eveningFadeStartHour)
                        && isNaN(NightLight.eveningFadeEndHour) && isNaN(NightLight.morningFadeStartHour)
                        && isNaN(NightLight.morningFadeEndHour),
                    "with the config unknown the arc gets no fade windows, whatever the schedule says")
                root.setFile(_getMode, "ok")
                root.getsBefore = root.lines(_getCalls).length
                NightLight._readConfig()
                break
            case 39:
                if (!root.ready(NightLight.configKnown && NightLight.schedule === "sun",
                        "a read that answers makes the config known again", 20))
                    return
                // a preset that holds only a static temperature answers without a transition mode
                root.getsBefore = root.lines(_getCalls).length
                root.setFile(_sunsetrConf, "static_temp=5000")
                NightLight._readConfig()
                break
            case 40:
                if (!root.ready(root.lines(_getCalls).length > root.getsBefore && !NightLight.configKnown,
                        "a reply without a transition mode is read", 20))
                    return
                root.check(NightLight._mode === "geo" && NightLight.schedule === "sun"
                        && NightLight.nightTemp === 3700 && NightLight.clockSunsetMin === 18 * 60 + 30,
                    "a reply without a transition mode leaves the config unknown and its values in place")
                root.getsBefore = root.lines(_getCalls).length
                root.config("geo", "3700", "18:30:00")
                NightLight._readConfig()
                break
            case 41:
                if (!root.ready(NightLight.configKnown && root.lines(_getCalls).length > root.getsBefore,
                        "a whole config is known again", 20))
                    return

                // a lookup outside a timezone switch, as a menu open does, only draws the arc
                root.setsBefore = root.lines(_setCalls).length
                NightLight._geoStarted = false
                NightLight._lookupLocation()
                break
            case 42:
                if (!root.ready(NightLight._geoResolved,
                        "the zone lookup resolves", 20))
                    return
                root.check(Math.abs(NightLight._autoLat - 56.95) < 0.0001 && Math.abs(NightLight._autoLon - 24.1) < 0.0001,
                    "the zone lookup finds the stand-in zone's coordinates")
                break
            case 43:
                if (++root.paused < 3) return
                root.paused = 0
                root.check(root.newSets().length === 0, "a lookup without a timezone switch writes nothing")
                TimeZoneWatch.switched()
                break
            case 44:
                if (!root.ready(root.newSets().length === 1 && NightLight.configKnown
                        && Math.abs(NightLight.configLatitude - 56.95) < 0.06,
                        "a timezone switch writes the new zone's location", 20))
                    return
                root.check(root.newSets()[0] === "latitude=56.95 longitude=24.10",
                    "the location goes to sunsetr in one write, to two decimals")
                root.check(Math.abs(NightLight._useLat - 56.95) < 0.06,
                    "the sun maths follow the written location")

                // a switch while a lookup for the old zone still runs
                root.setsBefore = root.lines(_setCalls).length
                root.setFile(_slowTz, "1")
                NightLight._geoStarted = false
                NightLight._lookupLocation()
                break
            case 45:
                // the stand-in reads the zone before its delay
                if (++root.paused < 2) return
                root.paused = 0
                root.setFile(_tzZone, "America/Chicago")
                TimeZoneWatch.switched()
                break
            case 46:
                if (!root.ready(root.newSets().length >= 1, "a switch during a lookup writes a location", 30))
                    return
                root.check(root.newSets()[0] === "latitude=41.85 longitude=-87.65",
                    "a switch during a lookup writes the new zone, not the one the lookup started on")
                break
            case 47:
                if (++root.paused < 6) return
                root.paused = 0
                root.check(root.newSets().length === 1, "the lookup that read the old zone writes nothing")
                root.setFile(_slowTz, "0")

                // the lifecycle checks below poke the check result by hand
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
            case 48: {
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
            case 49:
                if (!root.ready(root.lines(_unitState)[0] === "inactive" && !NightLight.enabled,
                        "the stand-in unit stops on the next toggle", 20))
                    return
                root.check(NightLight.lastError === "", "a stop that succeeds leaves no error")
                root.check(!ControlSurfaces.anyOpen && !NightLight._pollWanted,
                    "with every control surface shut the drift poll is off")

                // started outside the shell while nothing showed it
                root.setFile(_unitState, "active")
                QuickActionsState.open = true
                root.check(QuickActionsState.open && NightLight._pollWanted,
                    "an open control surface turns the drift poll on")
                break
            case 50: {
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
            case 51:
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
            case 52:
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
            case 53:
                // the stand-in reads the unit before its slow answer
                if (++root.paused < 2) return
                root.paused = 0
                root.setFile(_unitState, "inactive")
                root.markCalls()
                root.check(NightLight.toggleFresh() === "queued",
                    "a keybind toggle during a check queues behind it")
                break
            case 54:
                if (!root.ready(root.settled() && NightLight.enabled
                        && root.lines(_unitState)[0] === "active",
                        "the toggle waits for the check that follows the request", 40))
                    return
                root.check(root.toggledOnce("start"),
                    "a check already running when the keybind came does not decide its toggle")
                break
            case 55:
                // the check after the start is still on its slow answer
                if (++root.paused < 8) return
                root.paused = 0
                root.setFile(_slowCheck, "7")
                root.setFile(_unitState, "inactive")
                root.markCalls()
                root.check(NightLight.toggleFresh() === "queued",
                    "a keybind toggle queues behind a check that will time out")
                break
            case 56:
                if (!root.ready(NightLight.lastError === root.checkError,
                        "a check that times out reports its error", 40))
                    return
                break
            case 57:
                if (++root.paused < 4) return
                root.paused = 0
                root.check(root.count(root.lines(_systemctlCalls), "start") === root.startsBefore
                        && root.count(root.lines(_systemctlCalls), "stop") === root.stopsBefore,
                    "a check that times out drops the queued toggle")
                root.setFile(_slowCheck, "0")
                root.check(NightLight.toggleFresh() === "queued",
                    "a dropped toggle leaves the next keybind free to queue")
                break
            case 58:
                if (!root.ready(root.settled() && NightLight.enabled
                        && root.lines(_unitState)[0] === "active" && NightLight.lastError === "",
                        "the next keybind toggle starts the unit and clears the check error", 20))
                    return
                root.check(root.toggledOnce("start"), "the next keybind toggle sends one start")
                break
            case 59:
                // a keybind queues behind a slow check, a row tap settles it, and a second
                // keybind comes while that check, which read the unit before the tap, still runs
                if (++root.paused < 2) return
                root.paused = 0
                root.markCalls()
                root.setFile(_slowCheck, "3")
                root.check(NightLight.toggleFresh() === "queued",
                    "a keybind toggle queues behind a slow check")
                break
            case 60:
                // the stand-in reads the unit before its slow answer
                if (++root.paused < 2) return
                root.paused = 0
                QuickActionsState.open = true
                NightLight.toggle()
                QuickActionsState.close()
                root.check(!NightLight.enabled, "a row tap settles the waiting keybind by turning the unit off")
                break
            case 61: {
                const calls = root.lines(_systemctlCalls)
                if (!root.ready(root.count(calls, "stop") === root.stopsBefore + 1
                        && root.lines(_unitState)[0] === "inactive",
                        "the row tap stops the unit", 20))
                    return
                if (++root.paused < 2) return
                root.paused = 0
                root.setFile(_slowCheck, "0")
                root.check(NightLight.toggleFresh() === "queued",
                    "a second keybind toggle queues once the tap's stop has returned")
                break
            }
            case 62: {
                const calls = root.lines(_systemctlCalls)
                if (!root.ready(root.settled() && NightLight.enabled
                        && root.lines(_unitState)[0] === "active"
                        && root.count(calls, "start") === root.startsBefore + 1,
                        "the second keybind toggle starts the unit the tap stopped", 40))
                    return
                root.check(root.count(calls, "stop") === root.stopsBefore + 1,
                    "a check that read the unit before a row tap does not decide a later keybind toggle")
                NightLight.toggle()
                break
            }
            case 63:
                if (!root.ready(root.settled() && !NightLight.enabled
                        && root.lines(_unitState)[0] === "inactive",
                        "the unit stops before the cut-off start", 20))
                    return
                // a start that outlives systemctl's deadline
                root.setFile(_toggleMode, "hang")
                root.markCalls()
                NightLight.toggle()
                break
            case 64:
                if (!root.ready(NightLight.lastError === "sunsetr.service did not respond",
                        "a start cut off at its deadline reports it", 40))
                    return
                break
            case 65:
                if (!root.ready(root.settled() && !NightLight.enabled,
                        "the check after the cut-off start finds the unit stopped", 20))
                    return
                root.check(!NightLight._pollWanted && !NightLight.live,
                    "with every surface shut the cut-off start leaves no poll and no stream")
                // the next toggle clears the cut-off start's error
                root.setFile(_toggleMode, "ok")
                NightLight.toggle()
                break
            case 66:
                if (!root.ready(root.settled() && NightLight.enabled && NightLight.live
                        && NightLight.lastError === "",
                        "a toggle after the cut-off start clears its error and connects", 40))
                    return
                NightLight.toggle()
                break
            case 67:
                if (!root.ready(root.settled() && !NightLight.enabled
                        && root.lines(_unitState)[0] === "inactive",
                        "the unit stops before the slow writes", 20))
                    return
                // a write chained from a slow one's exit
                root.setFile(_slowSet, "3.2")
                root.setsBefore = root.lines(_setCalls).length
                root.doneBefore = root.lines(_setDone).length
                NightLight.setNightTemp(4200)
                break
            case 68:
                // 4300 waits behind 4200 and starts from its exit
                if (++root.paused < 2) return
                root.paused = 0
                NightLight.setNightTemp(4300)
                break
            case 69: {
                const done = root.lines(_setDone).slice(root.doneBefore)
                if (!root.ready(done.length >= 2, "a write started from the last one's exit answers", 40))
                    return
                root.check(done.length === 2 && done[0] === "night_temp=4200" && done[1] === "night_temp=4300",
                    "a write that follows a slow one gets a deadline of its own and lands last")
                root.setFile(_slowSet, "0.1")
                break
            }
            case 70: {
                if (++root.paused < 2) return
                root.paused = 0
                root.doneBefore = root.lines(_systemctlDone).length
                root.setFile(_slowCheck, "3.2")
                QuickActionsState.open = true
                QuickActionsState.close()
                break
            }
            case 71:
                // a second check asked for while the first runs follows from its exit
                if (++root.paused < 2) return
                root.paused = 0
                QuickActionsState.open = true
                QuickActionsState.close()
                break
            case 72: {
                const done = root.lines(_systemctlDone).slice(root.doneBefore)
                if (!root.ready(done.length >= 2 || NightLight.lastError.length > 0,
                        "a check started from the last one's exit answers", 40))
                    return
                root.check(done.length === 2 && root.count(done, "is-active 3.2") === 2
                        && NightLight.lastError === "",
                    "a check that follows a slow one gets a deadline of its own")
                // reading the stand-in's stop first keeps the view from skipping the write below as
                // one it already made
                root.check(root.lines(_unitState)[0] === "inactive", "the stand-in unit is stopped")
                // started outside the shell, so the slow check below reads it active
                root.setFile(_unitState, "active")
                root.setFile(_slowCheck, "3")
                root.markCalls()
                root.doneBefore = root.lines(_systemctlDone).length
                root.check(NightLight.toggleFresh() === "queued",
                    "a keybind toggle queues behind a slow check")
                break
            }
            case 73:
                // the stand-in reads the unit before its slow answer, then the unit stops outside
                // the shell and sunsetr goes away while that check still runs
                if (++root.paused < 2) return
                root.paused = 0
                root.setFile(_unitState, "inactive")
                _moveSunsetr.command = ["mv", root.base + "/bin/sunsetr", root.base + "/sunsetr-aside"]
                _moveSunsetr.running = true
                break
            case 74:
                if (_moveSunsetr.running) return
                SystemTools.refresh()
                break
            case 75:
                if (!root.ready(!NightLight.available, "the tool scan loses sunsetr", 12))
                    return
                root.check(NightLight.toggleFresh() === "unavailable",
                    "without sunsetr a keybind toggle is refused")
                _moveSunsetr.command = ["mv", root.base + "/sunsetr-aside", root.base + "/bin/sunsetr"]
                _moveSunsetr.running = true
                break
            case 76:
                if (_moveSunsetr.running) return
                SystemTools.refresh()
                break
            case 77:
                if (!root.ready(NightLight.available, "the tool scan finds sunsetr again", 12))
                    return
                root.check(root.lines(_systemctlDone).length === root.doneBefore,
                    "sunsetr comes back while the check that read the unit active still runs")
                root.setFile(_slowCheck, "0")
                root.check(NightLight.toggleFresh() === "queued",
                    "a keybind toggle after sunsetr comes back queues behind a check")
                break
            case 78: {
                const calls = root.lines(_systemctlCalls)
                if (!root.ready(root.settled() && root.count(calls, "start") + root.count(calls, "stop")
                        > root.startsBefore + root.stopsBefore,
                        "the keybind toggle after sunsetr comes back settles", 40))
                    return
                root.check(root.toggledOnce("start") && NightLight.enabled,
                    "a check that read the unit for a request dropped with the tool does not settle a later one")
                break
            }
            case 79:
                if (!root.ready(NightLight.live, "the follow connects after the last start", 40))
                    return
                // the tool goes missing while one write runs and another waits behind it
                root.setFile(_slowSet, "4.5")
                root.setsBefore = root.lines(_setCalls).length
                root.doneBefore = root.lines(_setDone).length
                NightLight.setNightTemp(4400)
                NightLight.setNightTemp(4500)
                // and a timezone switch whose lookup finishes after the tool has gone
                root.latBefore = NightLight.configLatitude
                root.setFile(_tzZone, "Europe/Riga")
                root.setFile(_slowTz, "4")
                TimeZoneWatch.switched()
                break
            case 80:
                // the write has to be running before the tool goes
                if (!root.ready(root.newSets().length === 1, "the write before the tool goes starts", 8))
                    return
                _moveSunsetr.command = ["mv", root.base + "/bin/sunsetr", root.base + "/sunsetr-aside"]
                _moveSunsetr.running = true
                break
            case 81:
                if (_moveSunsetr.running) return
                SystemTools.refresh()
                break
            case 82:
                if (!root.ready(!NightLight.available, "the tool scan loses sunsetr during a write", 12))
                    return
                root.check(root.lines(_setDone).length === root.doneBefore,
                    "the write is still running when the tool goes missing")
                // a zone lookup that finishes after the tool went missing
                NightLight._queueSet({ sunrise: "05:00:00" })
                break
            case 83:
                if (!root.ready(root.lines(_setDone).length > root.doneBefore && !NightLight._geoForSwitch,
                        "the running write and the switch's lookup finish without the tool", 30))
                    return
                // read before the tool comes back, whose config read would replace any coordinates
                root.check(NightLight._geoResolved && Math.abs(NightLight._autoLat - 56.95) < 0.0001
                        && NightLight.configLatitude === root.latBefore,
                    "a switch's location found while the tool is missing does not move the config's")
                root.getsBefore = root.lines(_getCalls).length
                _moveSunsetr.command = ["mv", root.base + "/sunsetr-aside", root.base + "/bin/sunsetr"]
                _moveSunsetr.running = true
                break
            case 84:
                if (_moveSunsetr.running) return
                SystemTools.refresh()
                break
            case 85:
                if (!root.ready(NightLight.available && root.lines(_getCalls).length > root.getsBefore,
                        "the config is read again once sunsetr is back", 20))
                    return
                if (++root.paused < 4) return
                root.paused = 0
                root.check(root.newSets().length === 1 && root.newSets()[0] === "night_temp=4400",
                    "writes queued or asked for while the tool was missing are dropped")
                root.setFile(_slowSet, "0.1")
                root.setFile(_slowTz, "0")
                root.finish()
                return
            }
            root.step++
        }
    }
}
