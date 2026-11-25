pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "services"

ShellRoot {
    id: root

    // Instantiate during root creation so PersistentProperties can transfer.
    readonly property int activeCount: Notifications.activeCount

    PersistentProperties {
        id: progress
        reloadableId: "silereNotificationReloadProbe"
        property int phase: 0
        property int checks: 0
        property int failures: 0
        property int liveId: -1
        property double arrivalTime: 0
        property bool retention: true
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }

    function _check(ok: bool, label: string): void {
        progress.checks++
        if (ok) return
        progress.failures++
        console.warn("PROBE-FAIL", label)
    }

    Process {
        id: sender
        command: ["notify-send", "--print-id", "--expire-time=0", "Reload probe"]
        stdout: StdioCollector {
            onStreamFinished: {
                progress.liveId = Number(this.text.trim())
                progress.arrivalTime = Date.now() - 15000
                const times = Notifications._cloneMap(Notifications._times)
                times[progress.liveId] = progress.arrivalTime
                Notifications._times = times
                Notifications.markSeen(progress.liveId)
                root._check(root.activeCount === 1, "real sender creates one live notification")
                progress.phase = 1
                Qt.callLater(function() { Quickshell.reload(false) })
            }
        }
    }

    // Wait for both asynchronous boundaries before asserting their final state.
    // The runner's deadline catches a readiness signal that never arrives.
    Timer {
        id: settle
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (!ShellSettings.ready || !Notifications._serverReady) return
            settle.stop()
            if (progress.phase === 0) {
                progress.retention = ShellSettings.notifHistoryPersistent
                root._check(ShellSettings.notifHistoryLimit === 100,
                    "raised history limit loads from the fixture file")
                Notifications.dnd = false
                ShellSettings.notifFullscreenSilence = false
                ShellSettings.notifPopupEnabled = true
                Notifications.clearHistory()
                for (let i = 1; i <= 60; i++)
                    Notifications._archiveNotification({ summary: "row " + i }, 1000 + i, 3000 + i)
                root._check(Notifications.historyCount === 60, "seed more than the default limit")
                sender.running = true
                return
            }
            const expected = progress.retention ? 60 : 0
            root._check(ShellSettings.notifHistoryLimit === 100
                    && ShellSettings.notifHistoryPersistent === progress.retention,
                "non-default settings survive the engine reload")
            root._check(Notifications.historyCount === expected,
                "reload retains all sixty rows or none according to the saved setting")
            root._check(root.activeCount === 1 && Notifications.list[0].id === progress.liveId,
                "server restores exactly one live object")
            root._check(Notifications.timeFor(progress.liveId) === progress.arrivalTime
                    && Notifications.isSeen(progress.liveId),
                "live age and read state survive reload with either retention setting")
            if (root.activeCount === 1)
                Notifications.dismissObject(progress.liveId, Notifications.list[0].notification, false)
            root._check(root.activeCount === 0 && Notifications.historyCount === expected + 1,
                "dismissal after reload archives exactly once")
            root._checkReadinessOrders()
            root._nextUrgencyCase()
        }
    }

    property int urgencyCase: 0
    readonly property var urgencyCases: [
        { dnd: true, bypass: true, urgency: "normal", active: 0 },
        { dnd: true, bypass: true, urgency: "critical", active: 1 },
        { dnd: true, bypass: false, urgency: "normal", active: 0 },
        { dnd: true, bypass: false, urgency: "critical", active: 0 },
        { dnd: false, bypass: false, urgency: "normal", active: 1 },
        { dnd: false, bypass: false, urgency: "critical", active: 1 }
    ]

    function _nextUrgencyCase(): void {
        if (root.urgencyCase >= root.urgencyCases.length) {
            root._nextBypassCase()
            return
        }
        const test = root.urgencyCases[root.urgencyCase]
        Notifications.dnd = test.dnd
        ShellSettings.notifCriticalBypass = test.bypass
        urgencySender.command = ["notify-send", "--print-id", "--expire-time=0",
            "--urgency=" + test.urgency, "Urgency probe " + root.urgencyCase]
        urgencySender.running = true
    }

    Process {
        id: urgencySender
        onExited: code => {
            const test = root.urgencyCases[root.urgencyCase]
            root._check(code === 0 && Notifications.activeCount === test.active,
                "real " + test.urgency + " notification with DND=" + test.dnd
                    + " and critical bypass=" + test.bypass)
            while (Notifications.list.length > 0) {
                const entry = Notifications.list[0]
                Notifications.dismissObject(entry.id, entry.notification, false)
            }
            root.urgencyCase++
            Qt.callLater(root._nextUrgencyCase)
        }
    }

    // Every case runs at normal urgency with DND on and the critical bypass off, so only the
    // app list can let a sender through. The fullscreen gate shares that one constant, but the
    // real Compositor derives its fullscreen flag from a live toplevel, which this private-bus
    // run has none of; it stays unprobed here rather than gaining a test-only hook.
    property int bypassCase: 0
    readonly property var bypassCases: [
        { label: "sender name listed", list: "Bypass App", name: "Bypass App", entry: "", active: 1 },
        { label: "desktop entry listed under a different name", list: "org.example.Bypass",
            name: "Other Name", entry: "org.example.Bypass", active: 1 },
        { label: "desktop entry listed with no usable name", list: "org.example.Bypass",
            name: "", entry: "org.example.Bypass", active: 1 },
        { label: "list entry and sender differ in case", list: "BYPASS app", name: "bypass APP", entry: "", active: 1 },
        { label: "desktop entry differs in case", list: "ORG.Example.Bypass",
            name: "Other Name", entry: "org.example.bypass", active: 1 },
        { label: "sender not on the list", list: "Bypass App", name: "Someone Else", entry: "org.example.Else", active: 0 },
        { label: "entry is only a prefix of the sender", list: "Bypass", name: "Bypass App", entry: "", active: 0 },
        { label: "entry is only a prefix of the desktop entry", list: "org.example",
            name: "Other Name", entry: "org.example.Bypass", active: 0 },
        { label: "sender is only a prefix of the entry", list: "Bypass App Pro", name: "Bypass App", entry: "", active: 0 },
        { label: "spaces and empty entries around a listed sender", list: " , Bypass App ,, ",
            name: "Bypass App", entry: "", active: 1 },
        { label: "sender listed between two others", list: "First App,Bypass App,Last App",
            name: "Bypass App", entry: "", active: 1 },
        { label: "doubled space inside a list entry", list: "Bypass  App", name: "Bypass App", entry: "", active: 1 },
        { label: "doubled space inside the sender name", list: "Bypass App", name: "Bypass  App", entry: "", active: 1 },
        { label: "empty list", list: "", name: "Bypass App", entry: "org.example.Bypass", active: 0 },
        { label: "separators alone", list: " , ,,", name: "Bypass App", entry: "", active: 0 },
        { label: "popups off hides a listed sender", list: "Bypass App", name: "Bypass App", entry: "",
            popup: false, active: 0 }
    ]

    function _nextBypassCase(): void {
        if (root.bypassCase === 0) {
            root._check(root._parsedBypass(" , Foo ,, ") === '["foo"]'
                    && root._parsedBypass("") === "[]"
                    && root._parsedBypass(" , ,,") === "[]"
                    && root._parsedBypass("A,B") === '["a","b"]',
                "app list parses to trimmed lowercase entries without empties")
        }
        if (root.bypassCase >= root.bypassCases.length) {
            ShellSettings.dndBypassApps = ""
            ShellSettings.notifPopupEnabled = true
            Notifications.dnd = false
            if (progress.failures === 0)
                console.warn("PROBE-RELOAD passed " + progress.checks + " checks")
            console.warn("PROBE-RELOAD-DONE")
            return
        }
        const test = root.bypassCases[root.bypassCase]
        Notifications.dnd = true
        ShellSettings.notifCriticalBypass = false
        ShellSettings.notifPopupEnabled = test.popup !== false
        ShellSettings.dndBypassApps = test.list
        const command = ["notify-send", "--print-id", "--expire-time=0", "--app-name=" + test.name]
        if (test.entry !== "") command.push("--hint=string:desktop-entry:" + test.entry)
        command.push("Bypass probe " + root.bypassCase)
        bypassSender.command = command
        bypassSender.running = true
    }

    function _parsedBypass(list: string): string {
        ShellSettings.dndBypassApps = list
        return JSON.stringify(Notifications._bypassApps)
    }

    Process {
        id: bypassSender
        onExited: code => {
            const test = root.bypassCases[root.bypassCase]
            root._check(code === 0 && Notifications.activeCount === test.active,
                test.label + " under DND (active " + test.active + ")")
            while (Notifications.list.length > 0) {
                const entry = Notifications.list[0]
                Notifications.dismissObject(entry.id, entry.notification, false)
            }
            root.bypassCase++
            Qt.callLater(root._nextBypassCase)
        }
    }

    function _checkReadinessOrders(): void {
        Notifications.clearHistory()
        ShellSettings._loaded = false
        Notifications._serverReady = false
        ShellSettings.notifHistoryPersistent = true
        ShellSettings.notifHistoryLimit = 20
        for (let i = 1; i <= 60; i++)
            Notifications._prependHistory({ id: i, summary: "early " + i })
        root._check(Notifications.historyCount === 60,
            "arrivals before settings readiness do not apply the default cap")
        for (let i = 61; i <= 120; i++)
            Notifications._prependHistory({ id: i, summary: "early " + i })
        root._check(Notifications.historyCount === ShellSettings.schemaFor("notifHistoryLimit").max,
            "early arrivals remain bounded by the schema maximum")
        Notifications._seen = { "1": true, "2": true }
        Notifications._times = { "1": 2000, "2": 2100 }
        Notifications._updateTimes = { "1": 2200, "2": 2300 }
        ShellSettings.notifHistoryLimit = 30
        ShellSettings._loaded = true
        root._check(Notifications.historyCount === 30,
            "settings readiness applies the configured limit")
        ShellSettings.notifHistoryPersistent = false
        root._check(Notifications.historyCount === 0
                && Notifications._times["1"] === 2000 && Notifications._seen["1"]
                && Notifications._updateTimes["1"] === 2200,
            "settings-first clearing cannot prune state before the server handoff")
        Notifications.list = [{ id: 1, time: 2000 }]
        Notifications._serverReady = true
        Notifications._pruneOrphanState()
        root._check(Notifications._times["1"] === 2000 && Notifications._seen["1"]
                && Notifications._updateTimes["1"] === 2200
                && Notifications._times["2"] === undefined,
            "completed handoff keeps live state and prunes orphans")

        ShellSettings._loaded = false
        ShellSettings.notifHistoryPersistent = true
        Notifications._prependHistory({ id: 1, summary: "server first" })
        Notifications._pruneOrphanState()
        ShellSettings.notifHistoryPersistent = false
        ShellSettings._loaded = true
        root._check(Notifications.historyCount === 0
                && Notifications._times["1"] === 2000 && Notifications._seen["1"]
                && Notifications._updateTimes["1"] === 2200,
            "server-first clearing also preserves live state")
        Notifications.list = []
        Notifications._pruneOrphanState()
    }
}
