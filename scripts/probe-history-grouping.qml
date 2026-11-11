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
        onObservedShapeChanged: {
            changes++
            root.noteEvaluation(observedShape, index)
        }
    }

    // The grouping reads the rows once per change into a table its readers share. Every
    // read is held against a walk of its run made afresh from the rows at that moment:
    // after each change, from bindings as they re-evaluate, and from inside the model's own
    // signals, heard before the grouping hears them and after
    property bool comparing: false
    property var stale: []

    function referenceKey(row, tail): string {
        if (row.run) return "run:" + String(row.run)
        return JSON.stringify([String(row.appName), HistoryRuns.dayKey(row.time), tail.id, tail.time])
    }

    function referenceBounds(rows, index: int): var {
        const n = rows.count
        if (index < 0 || index >= n) return { start: index, length: 1, critical: false, key: "" }
        const here = rows.get(index)
        let start = index
        while (start > 0 && HistoryRuns.sameRun(rows.get(start - 1), here)) start--
        let end = index
        while (end + 1 < n && HistoryRuns.sameRun(rows.get(end + 1), here)) end++
        let critical = false
        for (let i = start; i <= end && !critical; i++)
            critical = Number(rows.get(i).urgency) === 2
        return { start: start, length: end - start + 1, critical: critical,
            key: root.referenceKey(here, rows.get(end)) }
    }

    function referenceShape(rows, index: int): var {
        if (index < 0 || index >= rows.count)
            return { first: index === 0, section: true, header: true,
                length: 1, critical: false, key: "", open: false }
        const row = rows.get(index)
        const previous = index > 0 ? rows.get(index - 1) : null
        const section = !previous || HistoryRuns.dayKey(row.time) !== HistoryRuns.dayKey(previous.time)
        const header = section || !HistoryRuns.sameRun(previous, row)
        const run = root.referenceBounds(rows, index)
        return { first: index === 0, section: section, header: header,
            length: run.length, critical: run.critical, key: run.key,
            open: root.grouping._openRuns[run.key] === true }
    }

    function shapeText(s): string {
        return JSON.stringify([s.first, s.section, s.header, s.length, s.critical, s.key, s.open])
    }

    function boundsText(b): string {
        return JSON.stringify([b.start, b.length, b.critical, b.key])
    }

    // a shape held at an index, against the walk over the rows as they stand
    function shapeMismatch(shape, index: int): string {
        const want = root.shapeText(root.referenceShape(root.grouping.model, index))
        const got = root.shapeText(shape)
        return got === want ? "" : "row " + index + " holds " + got + " for " + want
    }

    // every index the rows have, one either side of them, and the bounds as well as the shape
    function readMismatch(): string {
        const rows = root.grouping.model
        for (let i = -1; i <= rows.count; i++) {
            const shape = root.shapeMismatch(root.grouping.shapeAt(i), i)
            if (shape) return shape
            const want = root.boundsText(root.referenceBounds(rows, i))
            const got = root.boundsText(root.grouping.runBounds(i))
            if (got !== want) return "row " + i + " bounds " + got + " for " + want
        }
        return ""
    }

    function noteRead(where: string): void {
        if (!root.comparing) return
        const wrong = root.readMismatch()
        if (wrong) root.stale.push(where + ": " + wrong)
    }

    function noteEvaluation(shape, index: int): void {
        if (!root.comparing) return
        const wrong = root.shapeMismatch(shape, index)
        if (wrong) root.stale.push("binding on " + index + " evaluated " + wrong)
    }

    // after a change: reads now, the bindings as they stand, and anything stale on the way
    function compareAfter(label: string): void {
        const wrong = [].concat(root.stale)
        const now = root.readMismatch()
        if (now) wrong.push("read after: " + now)
        const held = [root.shapeMismatch(observer.observedShape, observer.index)]
        for (let i = 0; i < root.watchers.length; i++)
            held.push(root.shapeMismatch(root.watchers[i].shape, root.watchers[i].index))
        for (let i = 0; i < held.length; i++)
            if (held[i]) wrong.push("binding held " + held[i])
        root.check(wrong.length === 0, label + " reads as a fresh walk of its run ("
            + wrong.slice(0, 3).join("; ") + ")")
        root.stale = []
    }

    property var watchers: []
    Component {
        id: watcherComponent

        QtObject {
            property int index: 0
            property var shape: root.grouping ? root.grouping.shapeAt(index) : ({})
            onShapeChanged: root.noteEvaluation(shape, index)
        }
    }

    // QML hears a signal in the order its handlers connected, so a listener made before the
    // grouping takes hold of a model hears each change before the grouping does, and one
    // made after it hears it after. A relabel is read only after: the model reports one once
    // it is done, and a reader heard before the grouping would read the table before it is
    // dropped
    Component {
        id: modelListener

        Connections {
            property string side: ""
            target: null
            function onRowsAboutToBeInserted() { root.noteRead(side + ", rows about to be inserted") }
            function onRowsInserted() { root.noteRead(side + ", rows inserted") }
            function onRowsAboutToBeRemoved() { root.noteRead(side + ", rows about to be removed") }
            function onRowsRemoved() { root.noteRead(side + ", rows removed") }
            function onCountChanged() { root.noteRead(side + ", count changed") }
            function onDataChanged() { if (side === "after") root.noteRead(side + ", data changed") }
        }
    }

    ListModel { id: replacement }

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

    function listenTo(model, side: string): var {
        return modelListener.createObject(root, { target: model, side: side })
    }

    // today three runs of A split by B and C, the middle one critical; yesterday A twice and D
    function seedMixed(): void {
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
        root.append("A", 202, root.day - 86400000 + 202)
        root.append("A", 201, root.day - 86400000 + 201)
        root.append("D", 100, root.day - 86400000 + 100)
    }

    function checkReadsMatchTheWalk(): void {
        root.seedMixed()
        root.comparing = true
        root.compareAfter("the seeded rows")
        root.grouping.setOpen(root.shape(4).key, true)
        root.compareAfter("a run opened")
        root.prepend("A", 903, root.day + 9003)
        root.compareAfter("an arrival on the newest run")
        root.prepend("E", 950, root.day + 9500)
        root.compareAfter("an arrival from another app")
        root.fileAt(3, root.entry("Late", 9015, root.day + 9001.5))
        root.compareAfter("a row of another app filed inside a run, splitting it")
        history.remove(0)
        root.compareAfter("the newest row cleared")
        history.remove(Math.floor(history.count / 2))
        root.compareAfter("a middle row cleared")
        history.remove(history.count - 1)
        root.compareAfter("the oldest row cleared")
        const whole = root.referenceBounds(history, 6)
        root.check(whole.length > 1, "the run cleared whole has more than one row")
        history.remove(whole.start, whole.length)
        root.compareAfter("a whole run cleared")
        history.remove(0)
        root.prepend("A", 904, root.day + 9004)
        root.compareAfter("a row replaced by its update in one turn")
        history.setProperty(2, "run", "relabelled")
        root.compareAfter("a row relabelled in place")
        history.setProperty(1, "urgency", 2)
        root.compareAfter("a row made critical in place")
        history.clear()
        root.compareAfter("history cleared")
        root.append("F", 63, root.day + 63)
        root.append("F", 62, root.day + 62)
        root.append("F", 61, root.day + 61)
        root.append("G", 60, root.day + 60)
        root.compareAfter("history refilled")

        // every row of a single run changes shape when one of them is relabelled, so a
        // binding that read the old labels shows whichever binding first read the table
        history.clear()
        for (let i = 0; i < 6; i++) root.append("H", 70 - i, root.day + 70 - i)
        root.compareAfter("a single run")
        history.setProperty(0, "run", "split")
        root.compareAfter("the newest row of a single run relabelled")

        // rows saved before runs were labelled read by app, day and oldest row until they are
        history.clear()
        const legacy = [["Old", 503], ["Old", 502], ["Old", 501], ["other", 400], ["Old", 302], ["Old", 301]]
        for (let i = 0; i < legacy.length; i++)
            history.append(root.entry(legacy[i][0], legacy[i][1], root.day + legacy[i][1]))
        root.compareAfter("unlabelled rows")
        HistoryRuns.labelMissing(history)
        root.compareAfter("unlabelled rows labelled on load")

        // a row filed this session above the same app's restored rows joins their run
        history.clear()
        history.append({ appName: "Seam", id: 4, time: root.day + 4, urgency: 1, run: "live" })
        history.append({ appName: "Seam", id: 3, time: root.day + 3, urgency: 1, run: "live" })
        history.append(root.entry("Seam", 2, root.day + 2))
        history.append(root.entry("Seam", 1, root.day + 1))
        HistoryRuns.labelMissing(history)
        root.compareAfter("restored rows labelled under rows filed this session")
        HistoryRuns.joinAt(history, 2)
        root.compareAfter("the rows filed this session joined to the restored run")
        root.comparing = false
    }

    function checkModelReplaced(): void {
        root.seedMixed()
        replacement.clear()
        replacement.append({ appName: "R", id: 3, time: root.day + 3, urgency: 1, run: "r" })
        replacement.append({ appName: "R", id: 2, time: root.day + 2, urgency: 2, run: "r" })
        replacement.append({ appName: "R", id: 1, time: root.day + 1, urgency: 1, run: "r" })
        replacement.append({ appName: "S", id: 0, time: root.day, urgency: 1, run: "s" })
        root.listenTo(replacement, "before")
        root.comparing = true
        root.grouping.model = replacement
        root.listenTo(replacement, "after")
        root.compareAfter("the grouping handed another model")
        replacement.insert(0, { appName: "R", id: 4, time: root.day + 4, urgency: 1, run: "r" })
        root.compareAfter("an arrival on the other model")
        history.remove(0)
        root.compareAfter("a change to the model given up")
        replacement.remove(2)
        root.compareAfter("a row cleared from the other model")
        replacement.setProperty(3, "run", "r")
        root.compareAfter("a relabel on the other model")
        root.grouping.model = history
        // the grouping has connected to history again, behind the listener made after it
        root.historyAfter.target = null
        root.historyAfter = root.listenTo(history, "after")
        root.compareAfter("the grouping handed its model back")
        history.remove(0)
        root.compareAfter("a change to the model taken back")
        root.comparing = false
    }

    // A grouping takes hold of its model's signals among the last steps of the page being
    // made, after the objects made after it have completed, and the page is made over
    // several turns of the event loop. A row that has read its shape by then, and a row filed
    // before the hold is taken, leave a change the grouping never hears of
    ListModel { id: lateRows }
    function checkChangeBeforeTheGroupingHears(): void {
        lateRows.clear()
        for (let i = 0; i < 3; i++)
            lateRows.append({ appName: "Late", id: i, time: root.day - i, urgency: 1, run: "late" })
        const project = Quickshell.env("SILERE_PROBE_ROOT") || ""
        // made as a file of the menu module, the one place the grouping's type is known. The
        // list is made last, so it completes first, and its row files a history row as it does
        const source = `
            import QtQuick
            Item {
                id: page
                width: 100; height: 100
                readonly property HistoryGrouping grouping: HistoryGrouping { model: lateRows; foldAt: 3 }
                property var early: page.grouping.model ? page.grouping.shapeAt(0) : null
                ListView {
                    width: 100; height: 100
                    model: 1
                    delegate: Item {
                        width: 10; height: 10
                        Component.onCompleted: lateRows.insert(0, { appName: "Other", id: 9,
                            time: ${root.day + 9}, urgency: 1, run: "other" })
                    }
                }
            }`
        let same = false
        try {
            const page = Qt.createQmlObject(source, root,
                "file://" + project + "/modules/menu/ProbeLateHearing.qml")
            same = lateRows.count === 4
            for (let i = -1; i <= lateRows.count && same; i++)
                same = root.shapeText(page.grouping.shapeAt(i))
                        === root.shapeText(root.referenceShape(lateRows, i))
                    && root.boundsText(page.grouping.runBounds(i))
                        === root.boundsText(root.referenceBounds(lateRows, i))
            page.destroy()
        } catch (e) {
            console.warn("PROBE-NOTE " + e)
            same = false
        }
        root.check(same, "a row filed before the grouping hears its model is read with the rest")
    }

    // the history model as the grouping sees it, counting every row read
    ListModel { id: bigHistory }
    QtObject {
        id: countedRows

        // moved once the grouping has heard of a change of rows, as the model's own count has
        // by the time the list moves its rows
        property int count: 0
        // a held object, not a property, which a binding reading rows would come to depend on
        readonly property var tally: ({ reads: 0 })
        signal rowsAboutToBeInserted()
        signal rowsInserted()
        signal rowsAboutToBeRemoved()
        signal rowsRemoved()
        signal rowsAboutToBeMoved()
        signal rowsMoved()
        signal modelAboutToBeReset()
        signal modelReset()
        signal layoutAboutToBeChanged()
        signal layoutChanged()
        signal dataChanged()

        function get(index: int): var {
            countedRows.tally.reads++
            return bigHistory.get(index)
        }

        property Connections forward: Connections {
            target: bigHistory
            function onRowsAboutToBeInserted() { countedRows.rowsAboutToBeInserted() }
            function onRowsInserted() {
                countedRows.rowsInserted()
                countedRows.count = bigHistory.count
            }
            function onRowsAboutToBeRemoved() { countedRows.rowsAboutToBeRemoved() }
            function onRowsRemoved() {
                countedRows.rowsRemoved()
                countedRows.count = bigHistory.count
            }
            function onDataChanged() { countedRows.dataChanged() }
            function onCountChanged() { countedRows.count = bigHistory.count }
        }
    }

    Component {
        id: bigReader

        QtObject {
            property var grouping: null
            property int index: 0
            property var shape: grouping ? grouping.shapeAt(index) : ({})
        }
    }

    // the list moves its rows' indexes inside the change, after the grouping has heard of
    // it: a model view's own connection is heard after every QML handler
    Component {
        id: indexShift

        Connections {
            property var readers: []
            target: bigHistory
            function onRowsInserted(parent, first: int, last: int) {
                for (let i = 0; i < readers.length; i++)
                    if (readers[i].index >= first) readers[i].index += last - first + 1
            }
            function onRowsRemoved(parent, first: int, last: int) {
                for (let i = 0; i < readers.length; i++) {
                    const reader = readers[i]
                    if (reader.index > last) reader.index -= last - first + 1
                    else if (reader.index >= first) reader.index = -1
                }
            }
        }
    }

    property var groupingComponent: null
    property var historyAfter: null

    // a folded run keeps every row built, each asking for its shape on every change; one
    // change reads each row a bounded number of times, however long the run
    function checkCostOfAChange(): void {
        const size = 100
        bigHistory.clear()
        for (let i = 0; i < size; i++)
            bigHistory.append({ appName: "Big", id: i, time: root.day - i, urgency: 1, run: "big" })
        const grouping = root.groupingComponent.createObject(root, { model: countedRows, foldAt: 3 })
        const readers = []
        for (let i = 0; i <= size; i++)
            readers.push(bigReader.createObject(root, { grouping: grouping, index: i }))
        const shift = indexShift.createObject(root, { readers: readers })
        const cost = change => {
            countedRows.tally.reads = 0
            change()
            return countedRows.tally.reads
        }
        const costs = {
            arrival: cost(() => bigHistory.insert(0,
                { appName: "Big", id: size, time: root.day + 1, urgency: 1, run: "big" })),
            newest: cost(() => bigHistory.remove(0)),
            middle: cost(() => bigHistory.remove(size / 2)),
            edit: cost(() => bigHistory.setProperty(size / 4, "urgency", 2))
        }
        let bounded = true
        for (const change in costs) bounded = bounded && costs[change] <= 3 * size
        root.check(bounded, "one change to a run of " + size + " reads at most " + 3 * size
            + " rows (" + JSON.stringify(costs) + ")")
        shift.target = null
        shift.destroy()
        for (let i = 0; i < readers.length; i++) readers[i].destroy()
        grouping.destroy()
    }

    Component.onCompleted: {
        const project = Quickshell.env("SILERE_PROBE_ROOT") || ""
        const component = Qt.createComponent("file://" + project + "/modules/menu/HistoryGrouping.qml")
        if (component.status === Component.Error) {
            root.check(false, component.errorString().trim())
        } else {
            root.groupingComponent = component
            root.listenTo(history, "before")
            root.grouping = component.createObject(root, { model: history, foldAt: 3 })
            root.historyAfter = root.listenTo(history, "after")
            root.check(root.grouping !== null, "history grouping creates")
        }
        if (!root.grouping) {
            console.warn("PROBE-HISTORY-DONE")
            return
        }
        for (let i = -1; i <= 16; i++)
            root.watchers.push(watcherComponent.createObject(root, { index: i }))
        root.watchers.push(watcherComponent.createObject(root, { index: 40 }))
        root.checkInsertionAndRetainedTail()
        root.checkTailDeletionAndReuse()
        root.checkSameTimestampAndDelimiters()
        root.checkConcurrentArrivalsAndRefold()
        root.checkOlderArrivalBelowTail()
        root.checkClearedTail()
        root.checkSeparateRunsStaySeparate()
        root.checkRunsSurviveRestart()
        root.checkDayBoundaryAndBoundShape()
        root.checkReadsMatchTheWalk()
        root.checkModelReplaced()
        root.checkChangeBeforeTheGroupingHears()
        root.checkCostOfAChange()
        if (root.failures === 0)
            console.warn("PROBE-HISTORY passed " + root.checks + " checks")
        console.warn("PROBE-HISTORY-DONE")
    }
}
