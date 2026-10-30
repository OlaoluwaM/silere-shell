pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "services/HistoryRuns.js" as HistoryRuns

// Exercises grouping through the same ListModel mutations that history uses.
// The sender is intentionally absent: test-history-grouping creates a private
// D-Bus session so no probe can reach the desktop notification daemon.
ShellRoot {
    id: root

    property var grouping: null
    property int checks: 0
    property int failures: 0
    readonly property double day: new Date(2026, 8, 5, 12, 0, 0).getTime()

    ListModel { id: history }

    QtObject {
        id: observer

        property int index: 0
        property var observedShape: root.grouping
            ? root.grouping.shapeAt(index) : ({})
        property int changes: 0
        onObservedShapeChanged: changes++
    }


    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    // every row carries the run role, as a normalized history entry does; an empty one is
    // a row saved before runs were labelled
    function entry(app: string, id: int, time: real, urgency: int): var {
        return { appName: app, id: id, time: time, urgency: urgency || 1, run: "" }
    }

    // files a row at a position the way the notification service does, labelling its run
    function fileAt(at: int, row): void {
        row.run = HistoryRuns.runForInsert(history, at, row)
        history.insert(at, row)
        HistoryRuns.splitAt(history, at)
    }

    // a row older than every row so far, as history files one that closed last
    function append(app: string, id: int, time: real, urgency: int): void {
        root.fileAt(history.count, root.entry(app, id, time, urgency))
    }

    function prepend(app: string, id: int, time: real, urgency: int): void {
        root.fileAt(0, root.entry(app, id, time, urgency))
    }

    // what saving and restoring history does to the rows, across a reload or a restart
    function saveAndRestore(): void {
        const saved = []
        for (let i = 0; i < history.count; i++) {
            const h = history.get(i)
            saved.push({ appName: h.appName, id: h.id, time: h.time, urgency: h.urgency, run: h.run })
        }
        const text = JSON.stringify(saved)
        history.clear()
        const restored = JSON.parse(text)
        for (let i = 0; i < restored.length; i++) history.append(restored[i])
        HistoryRuns.labelMissing(history)
    }

    function resetCase(): void {
        history.clear()
        root.grouping.reset()
    }

    function shape(index: int): var {
        return root.grouping.shapeAt(index)
    }

    function seedThreeRuns(): void {
        root.resetCase()
        root.append("A", 902, root.day + 9002)
        root.append("A", 901, root.day + 9001)
        root.append("A", 900, root.day + 9000)
        root.append("B", 800, root.day + 8000)
        root.append("A", 702, root.day + 7002)
        root.append("A", 701, root.day + 7001, 2)
        root.append("A", 700, root.day + 7000)
        root.append("C", 600, root.day + 6000)
        root.append("A", 502, root.day + 5002)
        root.append("A", 501, root.day + 5001)
        root.append("A", 500, root.day + 5000)
    }

    function checkInsertionAndRetainedTail(): void {
        root.seedThreeRuns()
        const newest = root.shape(0)
        const middle = root.shape(4)
        const oldest = root.shape(8)
        root.check(newest.length === 3 && middle.length === 3 && oldest.length === 3,
            "three separated same-app runs are grouped independently")
        root.check(middle.critical && !newest.critical && !oldest.critical,
            "a critical follower marks only its own folded run critical")
        root.check(newest.key !== middle.key && middle.key !== oldest.key,
            "same-app runs with distinct retained tails have distinct keys")
        root.grouping.setOpen(middle.key, true)
        root.prepend("D", 1000, root.day + 10000)
        root.check(root.shape(5).key === middle.key && root.shape(5).open,
            "an unrelated insertion above preserves an open run identity")

        // This was the ordinal collision: after deleting the oldest A run,
        // newest A became ordinal two and inherited middle A's open state.
        history.remove(9, 3)
        root.check(!root.shape(1).open && root.shape(5).open,
            "removing an older same-app run keeps expansion on its retained tail")
        root.check(root.shape(5).key === middle.key,
            "the middle run key survives deletion below it")
    }

    function checkTailDeletionAndReuse(): void {
        root.resetCase()
        root.append("Tail", 43, root.day + 43)
        root.append("Tail", 42, root.day + 42)
        root.append("Tail", 41, root.day + 41)
        const original = root.shape(0)
        root.grouping.setOpen(original.key, true)
        history.remove(2)
        root.check(!root.shape(0).open && root.shape(0).length === 2,
            "trimming a retained tail refolds the shortened run")

        root.resetCase()
        root.append("Reuse", 73, root.day + 73)
        root.append("Reuse", 72, root.day + 72)
        root.append("Reuse", 71, root.day + 71)
        root.grouping.setOpen(root.shape(0).key, true)
        history.clear()
        root.append("Reuse", 75, root.day + 75)
        root.append("Reuse", 74, root.day + 74)
        root.append("Reuse", 71, root.day + 71)
        root.check(!root.shape(0).open,
            "history clearing prunes an open key before an identical group returns")

        root.resetCase()
        root.append("Remove", 93, root.day + 93)
        root.append("Remove", 92, root.day + 92)
        root.append("Remove", 91, root.day + 91)
        root.grouping.setOpen(root.shape(0).key, true)
        history.remove(0, 3)
        root.append("Remove", 93, root.day + 93)
        root.append("Remove", 92, root.day + 92)
        root.append("Remove", 91, root.day + 91)
        root.check(!root.shape(0).open,
            "removing a run prunes its key before an identical group returns")
    }

    function checkSameTimestampAndDelimiters(): void {
        root.resetCase()
        const app = "A|B,[\"tail\"]"
        root.append(app, 12, root.day)
        root.append(app, 11, root.day)
        root.append(app, 10, root.day)
        root.append("separator", 9, root.day)
        root.append(app, 22, root.day)
        root.append(app, 21, root.day)
        root.append(app, 20, root.day)
        const first = root.shape(0)
        const second = root.shape(4)
        root.check(first.key !== second.key,
            "equal timestamps and delimiter-bearing app names still yield unique keys")
        root.grouping.setOpen(second.key, true)
        root.check(!root.shape(0).open && root.shape(4).open,
            "delimiter-bearing names retain expansion on their own group")

        root.resetCase()
        root.append("Collision", 4, root.day + 304)
        root.append("Collision", 3, root.day + 303)
        root.append("Collision", 1, root.day + 300)
        root.append("separator", 0, root.day + 200)
        root.append("Collision", 4, root.day + 104)
        root.append("Collision", 3, root.day + 103)
        root.append("Collision", 1, root.day + 100)
        const recent = root.shape(0)
        const older = root.shape(4)
        root.check(recent.key !== older.key,
            "simultaneous runs separate a reused server id by retained-tail time")
        root.grouping.setOpen(older.key, true)
        root.check(!root.shape(0).open && root.shape(4).open,
            "a reused server id leaves expansion on the matching retained timestamp")
    }

    function checkConcurrentArrivalsAndRefold(): void {
        root.resetCase()
        root.prepend("Burst", 31, root.day + 31)
        root.prepend("Burst", 32, root.day + 32)
        root.prepend("Burst", 33, root.day + 33)
        const burst = root.shape(0)
        root.check(burst.length === 3 && burst.header && !burst.open,
            "synchronous arrivals form one initially folded group")
        root.grouping.setOpen(burst.key, true)
        root.prepend("Burst", 34, root.day + 34)
        root.check(root.shape(0).key === burst.key && root.shape(0).open,
            "a fourth synchronous arrival retains the expanded run tail")
        root.grouping.reset()
        root.check(!root.shape(0).open,
            "page refold clears transient expansion state")
    }

    function checkOlderArrivalBelowTail(): void {
        root.resetCase()
        root.append("Late", 403, root.day + 403)
        root.append("Late", 402, root.day + 402)
        root.append("Late", 401, root.day + 401)
        root.append("separator", 300, root.day + 300)
        root.grouping.setOpen(root.shape(0).key, true)
        root.fileAt(3, root.entry("Late", 400, root.day + 400))
        root.check(root.shape(0).length === 4 && root.shape(0).open,
            "an older same-app arrival below the tail keeps the run open")
        root.check(root.shape(4).header && !root.shape(4).open,
            "the run below an older arrival keeps its own state")

        root.resetCase()
        root.append("Late", 403, root.day + 403)
        root.append("Late", 402, root.day + 402)
        root.append("Late", 401, root.day + 401)
        root.grouping.setOpen(root.shape(0).key, true)
        root.fileAt(3, root.entry("Other", 400, root.day + 400))
        root.check(root.shape(0).open && root.shape(3).header && !root.shape(3).open,
            "an older arrival from another app leaves the open run and starts its own")

        root.resetCase()
        root.append("Late", 403, root.day + 403)
        root.append("Late", 402, root.day + 402)
        root.append("Late", 401, root.day + 401)
        root.fileAt(3, root.entry("Late", 400, root.day + 400))
        root.check(!root.shape(0).open,
            "an older arrival below a folded run leaves it folded")
    }

    function checkClearedTail(): void {
        root.resetCase()
        root.append("Clear", 404, root.day + 404)
        root.append("Clear", 403, root.day + 403)
        root.append("Clear", 402, root.day + 402)
        root.append("Clear", 401, root.day + 401)
        root.append("separator", 300, root.day + 300)
        root.grouping.setOpen(root.shape(0).key, true)
        history.remove(3)
        root.check(root.shape(0).length === 3 && root.shape(0).open,
            "clearing an open run's tail keeps the rest of the run open")
        root.check(root.shape(3).header && !root.shape(3).open,
            "the run below a cleared tail keeps its own state")

        // the cleared tail sits on a day boundary with the same app on both sides
        root.resetCase()
        root.append("Clear", 304, root.day + 304)
        root.append("Clear", 303, root.day + 303)
        root.append("Clear", 302, root.day + 302)
        root.append("Clear", 204, root.day - 86400000 + 204)
        root.append("Clear", 203, root.day - 86400000 + 203)
        root.append("Clear", 202, root.day - 86400000 + 202)
        root.append("Clear", 201, root.day - 86400000 + 201)
        root.append("Clear", 104, root.day - 2 * 86400000 + 104)
        root.append("Clear", 103, root.day - 2 * 86400000 + 103)
        root.append("Clear", 102, root.day - 2 * 86400000 + 102)
        root.grouping.setOpen(root.shape(3).key, true)
        history.remove(6)
        root.check(root.shape(3).length === 3 && root.shape(3).open,
            "clearing the tail of an open run in a middle day keeps it open")
        root.check(!root.shape(0).open && !root.shape(6).open,
            "the runs on the neighbouring days keep their own state")

        // a whole cleared run never hands its state to the same app's run on the day above
        history.remove(3, 3)
        root.check(!root.shape(0).open && !root.shape(3).open,
            "clearing an open run leaves the same app's run on the day above folded")

        // nor does a removal that takes a whole run along with rows of another app above it
        root.resetCase()
        root.append("Span", 503, root.day + 503)
        root.append("Span", 502, root.day + 502)
        root.append("Span", 501, root.day + 501)
        root.append("other", 400, root.day + 400)
        root.append("Span", 303, root.day + 303)
        root.append("Span", 302, root.day + 302)
        root.append("Span", 301, root.day + 301)
        root.grouping.setOpen(root.shape(4).key, true)
        history.remove(3, 4)
        root.check(!root.shape(0).open,
            "a removal spanning more than the open run hands its state to no run above")
    }

    function seedSplitRuns(): void {
        root.resetCase()
        root.append("Kitty", 302, root.day + 302)
        root.append("Kitty", 301, root.day + 301)
        root.append("Kitty", 300, root.day + 300)
        root.append("separator", 200, root.day + 200)
        root.append("Kitty", 106, root.day + 106)
        root.append("Kitty", 105, root.day + 105)
        root.append("Kitty", 104, root.day + 104)
        root.append("Kitty", 103, root.day + 103)
    }

    function ids(start: int, count: int): string {
        const out = []
        for (let i = start; i < start + count && i < history.count; i++) out.push(history.get(i).id)
        return out.join(",")
    }

    // the logged case: clearing the row between two runs of one app made them one run of
    // seven, and the next Clear on that stack took both
    function checkSeparateRunsStaySeparate(): void {
        root.seedSplitRuns()
        history.remove(3)
        root.check(root.shape(0).length === 3 && root.shape(3).header
                && root.shape(3).length === 4 && root.shape(0).key !== root.shape(3).key,
            "clearing the row between two runs of one app leaves two runs (" + root.grouping.describe() + ")")
        const upper = root.shape(0)
        history.remove(0, upper.length)
        root.check(history.count === 4 && root.ids(0, 4) === "106,105,104,103",
            "a Clear on the upper run then takes only its own rows (left " + root.ids(0, history.count) + ")")

        root.seedSplitRuns()
        root.grouping.setOpen(root.shape(0).key, true)
        history.remove(3)
        root.check(root.shape(0).open && !root.shape(3).open,
            "the open upper run stays open and the lower one folded once they meet")

        root.seedSplitRuns()
        root.grouping.setOpen(root.shape(4).key, true)
        history.remove(3)
        root.check(!root.shape(0).open && root.shape(3).open,
            "the open lower run stays open and the upper one folded once they meet")

        // a notification that closed late lands inside a run; the halves stay apart once it goes
        root.resetCase()
        root.append("Kitty", 404, root.day + 404)
        root.append("Kitty", 403, root.day + 403)
        root.append("Kitty", 402, root.day + 402)
        root.append("Kitty", 401, root.day + 401)
        root.fileAt(2, root.entry("Late", 4025, root.day + 402.5))
        root.check(root.shape(0).length === 2 && root.shape(3).header && root.shape(3).length === 2,
            "a row of another app filed inside a run splits it in two")
        history.remove(2)
        root.check(root.shape(0).length === 2 && root.shape(2).header && root.shape(2).length === 2,
            "clearing that row leaves the halves as two runs")

        // consecutive arrivals still stack, under the run below and the row above alike
        root.resetCase()
        root.prepend("Burst", 1, root.day + 1)
        root.prepend("Burst", 2, root.day + 2)
        root.prepend("Burst", 3, root.day + 3)
        root.check(root.shape(0).length === 3 && root.shape(0).header,
            "notifications that arrive in a row from one app still form one run")
    }

    // runs are saved with their rows, so a restart cannot join two of them
    function checkRunsSurviveRestart(): void {
        root.seedSplitRuns()
        history.remove(3)
        const upperKey = root.shape(0).key
        root.saveAndRestore()
        root.check(root.shape(0).length === 3 && root.shape(3).header && root.shape(3).length === 4,
            "two runs of one app side by side stay two after a restart (" + root.grouping.describe() + ")")
        root.check(root.shape(0).key === upperKey,
            "a run keeps its identity across a restart")

        // rows saved before runs were labelled take the old adjacency rule on load
        root.resetCase()
        const legacy = [["Old", 503], ["Old", 502], ["Old", 501], ["other", 400],
                        ["Old", 302], ["Old", 301], ["Old", 300]]
        for (let i = 0; i < legacy.length; i++)
            history.append(root.entry(legacy[i][0], legacy[i][1], root.day + legacy[i][1]))
        HistoryRuns.labelMissing(history)
        let labelled = true
        for (let i = 0; i < history.count; i++) labelled = labelled && history.get(i).run.length > 0
        root.check(labelled && root.shape(0).length === 3 && root.shape(3).length === 1
                && root.shape(4).length === 3 && root.shape(0).key !== root.shape(4).key,
            "unlabelled rows from an older file are grouped by adjacency on load")
        history.remove(3)
        root.check(root.shape(0).length === 3 && root.shape(3).header && root.shape(3).length === 3,
            "once labelled, those runs stay apart when the row between them goes")
    }

    function checkDayBoundaryAndBoundShape(): void {
        root.resetCase()
        root.append("Day", 303, root.day + 303)
        root.append("Day", 302, root.day + 302)
        root.append("Day", 301, root.day + 301)
        root.append("Day", 203, root.day - 86400000 + 203)
        root.append("Day", 202, root.day - 86400000 + 202)
        root.append("Day", 201, root.day - 86400000 + 201)
        root.check(root.shape(0).length === 3 && root.shape(3).length === 3
                && root.shape(3).section && root.shape(3).header,
            "the same app starts a distinct run at a day boundary")

        root.resetCase()
        const before = observer.changes
        root.append("Bound", 13, root.day + 13)
        root.append("Bound", 12, root.day + 12)
        root.append("Bound", 11, root.day + 11)
        root.check(observer.observedShape.length === 3 && observer.observedShape.header,
            "a QML binding observes grouped model insertions")
        const afterInsert = observer.changes
        root.grouping.setOpen(observer.observedShape.key, true)
        root.check(observer.observedShape.open && observer.changes > afterInsert
                && afterInsert > before,
            "a QML binding observes expansion state changes")

        // a pooled delegate holds its last index while history shortens under it
        observer.index = 2
        history.remove(2)
        root.check(observer.observedShape.length === 1 && !observer.observedShape.open,
            "a binding left on a removed index reads a lone row rather than past the end")
        observer.index = 0
    }

    Component.onCompleted: {
        const project = Quickshell.env("SILERE_PROBE_ROOT") || ""
        const component = Qt.createComponent("file://" + project + "/modules/menu/HistoryGrouping.qml")
        if (component.status === Component.Error) {
            root.check(false, component.errorString().trim())
        } else {
            root.grouping = component.createObject(root, { model: history, foldAt: 3 })
            root.check(root.grouping !== null, "history grouping creates")
        }
        if (!root.grouping) {
            console.warn("PROBE-HISTORY-DONE")
            return
        }
        root.checkInsertionAndRetainedTail()
        root.checkTailDeletionAndReuse()
        root.checkSameTimestampAndDelimiters()
        root.checkConcurrentArrivalsAndRefold()
        root.checkOlderArrivalBelowTail()
        root.checkClearedTail()
        root.checkSeparateRunsStaySeparate()
        root.checkRunsSurviveRestart()
        root.checkDayBoundaryAndBoundShape()
        if (root.failures === 0)
            console.warn("PROBE-HISTORY passed " + root.checks + " checks")
        console.warn("PROBE-HISTORY-DONE")
    }
}
