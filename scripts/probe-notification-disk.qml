pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "services"

ShellRoot {
    id: root

    readonly property string phase: String(Quickshell.env("SILERE_NOTIFICATION_DISK_PHASE") || "")
    property int checks: 0
    property int failures: 0
    property bool started: false
    property bool senderStarted: false
    property bool sawWriteFailure: false
    readonly property int historyCount: Notifications.historyCount

    PersistentProperties {
        id: reloadProgress
        reloadableId: "silereDiskReloadProbe"
        property bool requested: false
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }

    function check(ok: bool, label: string): void {
        checks++
        if (ok) return
        failures++
        console.warn("PROBE-FAIL", label)
    }

    function finish(): void {
        if (failures === 0) console.warn("PROBE-DISK " + phase + " passed " + checks + " checks")
        console.warn("PROBE-DISK-DONE")
    }

    function archive(appName: string, summary: string, id: int, time: real): void {
        Notifications._archiveNotification({ appName: appName, summary: summary }, id, time)
    }

    Timer {
        id: finishTimer
        interval: 1000
        repeat: false
        onTriggered: root.finish()
    }

    Process {
        id: sender
        command: ["notify-send", "--expire-time=0", "Disk restore arrival"]
        onExited: code => root.check(code === 0, "private-bus sender exits successfully")
    }

    Process {
        id: makeReadOnly
        command: ["chmod", "0500", ConfigStore.directory]
        onExited: code => {
            root.check(code === 0, "history directory can be made read-only")
            root.archive("Retry", "write retry", 88, 8800)
        }
    }

    Timer {
        id: poll
        interval: 25
        running: true
        repeat: true
        onTriggered: {
            if (root.phase.startsWith("delayed-") && !root.started) {
                if (!ShellSettings.ready || !Notifications._persistentReady
                        || !Notifications._diskReadable) return
                root.started = true
                root.check(!Notifications._diskRestored && Notifications.historyCount === 0,
                    "the real disk load is held before the first history merge")
                root.archive("Current", "keep", 90, 9000)
                root.archive("Current", "delete", 91, 9100)
                if (root.phase === "delayed-row") Notifications.removeFromHistory(0)
                else if (root.phase === "delayed-run") Notifications.removeRunFromHistory(0, 1)
                else Notifications.clearHistory()
                root.check(Notifications.historyCount === (root.phase === "delayed-clear" ? 0 : 1),
                    "the requested deletion changes only the selected in-memory rows")
                Notifications._diskLoadSettled = true
                Notifications._tryRestoreDisk()
                const ids = []
                for (let i = 0; i < Notifications.historyCount; i++)
                    ids.push(Notifications.historyModel.get(i).id)
                root.check(JSON.stringify(ids.sort((a, b) => a - b))
                        === (root.phase === "delayed-clear" ? "[]" : "[11,12,13,90]"),
                    "single-row and run deletion preserve disk rows; clear-all suppresses them")
                finishTimer.start()
                poll.stop()
                return
            }
            if (!ShellSettings.ready || !Notifications._persistentReady || !Notifications._diskRestored)
                return
            if (Notifications.historyPersistenceError.length > 0) root.sawWriteFailure = true

            if (root.phase === "seed" && !root.started) {
                root.started = true
                Notifications.clearHistory()
                Notifications._seen = { "1": true }
                Notifications._times = { "1": 1001 }
                for (let i = 2; i <= 8; i++) root.archive("Seed", "row " + i, i, 1000 + i)
                root.archive("Seed", "recycled id", 1, 1001)
                root.archive("Alpha", "same text", 41, 4100)
                root.archive("Beta", "same text", 42, 4100)
                Notifications.removeFromHistory({ id: 41, time: 4100,
                    appName: "Alpha", summary: "same text" })
                const retained = Notifications.historyModel.get(0)
                root.check(retained.id === 42 && retained.appName === "Beta"
                        && retained.summary === "same text",
                    "identity deletion keeps the equal-time, equal-summary row from another app")
                root.check(Notifications.historyModel.get(0).sessionCurrent,
                    "seed history belongs to the current process")
                finishTimer.start()
                return
            }

            if (root.phase === "restore") {
                if (!root.started) {
                    root.started = true
                    root.check(Notifications.historyCount === 5,
                        "configured limit bounds prior-process disk history")
                    let foundOld = false
                    for (let i = 0; i < Notifications.historyCount; i++) {
                        const entry = Notifications.historyModel.get(i)
                        if (entry.id === 1) {
                            foundOld = !entry.sessionCurrent && Notifications.isSeen(1)
                                    && Notifications.timeFor(1) === 1001
                        }
                    }
                    root.check(foundOld, "disk rows are archived and retain their stored state before id reuse")
                    sender.running = true
                    root.senderStarted = true
                    return
                }
                if (root.senderStarted && Notifications.activeCount === 1) {
                    const entry = Notifications.list[0]
                    root.check(entry.id === 1 && !Notifications.isSeen(entry.id)
                            && Notifications.timeFor(entry.id) !== 1001,
                        "a recycled server id cannot inherit prior-process state")
                    Notifications.dismissObject(entry.id, entry.notification, false)
                    root.check(Notifications.historyCount === 5,
                        "archiving the live recycled id keeps history bounded")
                    finishTimer.start()
                    poll.running = false
                }
                return
            }

            if (root.phase === "off" && !root.started) {
                root.started = true
                root.check(Notifications.historyCount === 0,
                    "persistence-off startup does not restore disk history")
                root.archive("Off", "memory only", 99, 9900)
                root.check(Notifications.historyCount === 1,
                    "persistence-off arrivals still accumulate until restart")
                finishTimer.start()
                return
            }

            if (root.phase === "late") {
                if (!root.started) {
                    root.started = true
                    sender.running = true
                    root.senderStarted = true
                    return
                }
                if (root.senderStarted && Notifications.activeCount === 1) {
                    const live = Notifications.list[0]
                    const staleSeen = {}
                    const staleTimes = {}
                    staleSeen[String(live.id)] = true
                    staleTimes[String(live.id)] = 1001
                    Notifications._restoreFromDisk(JSON.stringify({
                        __version: 1,
                        history: [{ id: live.id, appName: "Old", summary: "archived",
                            time: 1001, sessionCurrent: false }],
                        seen: staleSeen, times: staleTimes
                    }))
                    root.check(!Notifications.isSeen(live.id)
                            && Notifications.timeFor(live.id) !== 1001,
                        "a late disk read cannot mark a fresh recycled id seen")
                    finishTimer.start()
                    poll.running = false
                }
                return
            }

            if ((root.phase === "future" || root.phase === "future-off") && !root.started) {
                root.started = true
                const enabled = root.phase === "future"
                root.check(Notifications.historyCount === (enabled ? 1 : 0),
                    "compatible future rows restore only when persistence is enabled")
                if (enabled && Notifications.historyCount === 1) {
                    const entry = Notifications.historyModel.get(0)
                    root.check(entry.summary === "future" && !entry.sessionCurrent
                            && Notifications.isSeen(1) && Notifications.timeFor(1) === 1001,
                        "future rows retain compatible fields and prior-process identity")
                    Notifications.removeFromHistory(0)
                }
                root.check(Notifications.historyPersistenceError.indexOf("newer version") >= 0,
                    "future file protection remains reported after in-memory edits")
                root.archive("Future", "memory only", 77, 7700)
                finishTimer.start()
                return
            }

            if (root.phase === "guard" && !root.started) {
                root.started = true
                root.check(Notifications.historyPersistenceError.length > 0,
                    "unreadable or future history reports that its file was preserved")
                root.archive("Guard", "must not overwrite", 77, 7700)
                finishTimer.start()
                return
            }

            if (root.phase === "settings-order" && !root.started) {
                root.started = true
                Notifications.clearHistory()
                ShellSettings._loaded = false
                ShellSettings.notifHistoryPersistent = false
                Notifications._diskHistoryMayRestore = true
                Notifications._diskRestored = false
                Notifications._diskReadable = true
                Notifications._diskRaw = JSON.stringify({ __version: 1,
                    history: [{ id: 55, appName: "Saved", summary: "Keep me", time: 5500 }],
                    seen: {}, times: {} })
                Notifications._tryRestoreDisk()
                root.check(!Notifications._diskRestored && Notifications.historyCount === 0,
                    "disk restoration waits for saved settings over a false initial default")
                ShellSettings.notifHistoryPersistent = true
                ShellSettings._loaded = true
                root.check(Notifications._diskRestored && Notifications.historyCount === 1,
                    "a saved true setting restores history after a false initial default")

                // Replay the same ordering at the reload boundary, where history
                // has already been saved in PersistentProperties.
                ShellSettings._loaded = false
                ShellSettings.notifHistoryPersistent = false
                Notifications._restorePersistentState()
                root.check(Notifications.historyCount === 1,
                    "reload history survives until the saved setting is known")
                ShellSettings.notifHistoryPersistent = true
                ShellSettings._loaded = true
                root.check(Notifications.historyCount === 1,
                    "saved UI persistence wins on reload as well as disk startup")
                finishTimer.start()
                return
            }

            if (root.phase === "clear-reload" && !root.started) {
                root.started = true
                if (!reloadProgress.requested) {
                    root.check(Notifications.historyCount > 0, "reload fixture starts with saved history")
                    Notifications.clearHistory()
                    reloadProgress.requested = true
                    poll.stop()
                    Qt.callLater(function() { Quickshell.reload(false) })
                } else {
                    root.check(Notifications.historyCount === 0,
                        "a reload before the disk debounce cannot resurrect cleared history")
                    finishTimer.start()
                }
                return
            }

            if (root.phase === "live-markers") {
                if (reloadProgress.requested) {
                    if (root.started || !Notifications._serverReady) return
                    root.started = true
                    root.check(Notifications.activeCount === 0
                            && Object.keys(Notifications._liveIds).length === 0,
                        "reload-time DND rejection removes obsolete live identity markers")
                    finishTimer.start()
                } else if (!root.senderStarted) {
                    root.senderStarted = true
                    sender.running = true
                } else if (Notifications.activeCount === 1) {
                    Notifications.dnd = true
                    reloadProgress.requested = true
                    poll.stop()
                    Qt.callLater(function() { Quickshell.reload(false) })
                }
                return
            }

            if (root.phase === "calendar" && !root.started) {
                if (CalendarState.persistenceError.length === 0) return
                root.started = true
                root.check(CalendarState.persistenceError.indexOf("newer version") >= 0,
                    "a future calendar file stays protected")
                CalendarState.toggleMark(2026, 0, 1)
                finishTimer.start()
                return
            }

            if (root.phase === "retry" && !root.started) {
                root.started = true
                makeReadOnly.running = true
                return
            }
            if (root.phase === "retry" && root.started && root.sawWriteFailure
                    && Notifications.historyPersistenceError.length === 0) {
                root.check(true, "failed write retries after ConfigStore repairs permissions")
                finishTimer.start()
                poll.running = false
            }
        }
    }
}
