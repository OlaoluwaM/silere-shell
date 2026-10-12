pragma ComponentBehavior: Bound

import QtQuick

// The notification service owns history. This object owns only the menu's
// app/day grouping and the expansion state that belongs to those groups.
QtObject {
    id: root

    required property var model
    property int foldAt: 3
    property var _openRuns: ({})

    signal modelAboutToChange()

    function dayKey(ms): string {
        const d = new Date(Number(ms || Date.now()))
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }

    // The run tail survives arrivals newer than it. It identifies the retained
    // group without confusing equal timestamps or reused server ids; an older
    // arrival that history slots in below the tail becomes the new tail, and
    // _carryOpenTail moves the open state over to it.
    function runKey(app: string, day: string, tail): string {
        return JSON.stringify([app, day, tail.id, tail.time])
    }

    function runBounds(index: int): var {
        const rows = root.model
        const n = rows.count
        if (index < 0 || index >= n) return { start: index, length: 1, critical: false, key: "" }

        const here = rows.get(index)
        const app = String(here.appName)
        const day = root.dayKey(here.time)
        let start = index
        while (start > 0) {
            const above = rows.get(start - 1)
            if (String(above.appName) !== app || root.dayKey(above.time) !== day) break
            start--
        }
        let end = index
        while (end + 1 < n) {
            const below = rows.get(end + 1)
            if (String(below.appName) !== app || root.dayKey(below.time) !== day) break
            end++
        }

        let critical = false
        for (let i = start; i <= end && !critical; i++)
            critical = Number(rows.get(i).urgency) === 2

        const tail = rows.get(end)
        return { start: start, length: end - start + 1, critical: critical,
            key: root.runKey(app, day, tail) }
    }

    function shapeAt(index: int): var {
        const rows = root.model
        const row = rows.get(index)
        const previous = index > 0 ? rows.get(index - 1) : null
        const section = !previous || root.dayKey(row.time) !== root.dayKey(previous.time)
        const header = section || String(row.appName) !== String(previous.appName)
        const run = root.runBounds(index)
        return { first: index === 0, section: section, header: header,
            length: run.length, critical: run.critical, key: run.key,
            open: root._openRuns[run.key] === true }
    }

    // A fresh object is necessary because QML bindings observe the reference.
    function setOpen(key: string, open: bool): void {
        const next = {}
        for (const known in root._openRuns) next[known] = root._openRuns[known]
        if (open) next[key] = true
        else delete next[key]
        root._openRuns = next
    }

    function reset(): void {
        root._openRuns = ({})
    }

    // History files a notification by arrival when it closes, so one that
    // outlived newer ones from its app lands under the run the user opened.
    function _carryOpenTail(first: int, last: int): void {
        if (first <= 0) return
        const rows = root.model
        const above = rows.get(first - 1)
        const app = String(above.appName)
        const day = root.dayKey(above.time)
        // the row above was its run's tail only when nothing of that run follows the insert
        const below = last + 1 < rows.count ? rows.get(last + 1) : null
        if (below && String(below.appName) === app && root.dayKey(below.time) === day) return
        const was = root.runKey(app, day, above)
        if (root._openRuns[was] !== true) return
        const now = root.runBounds(first - 1).key
        if (now !== was) root.setOpen(now, true)
    }

    // the row that becomes an open run's tail once a removal lands
    property int _tailHeir: -1

    // Clearing the tail of an open run must not refold the rows still in it. The
    // row above takes the open state only when it stays in that run: a cleared
    // run never hands its state to the run above
    function _noteRemovedTail(first: int, last: int): void {
        root._tailHeir = -1
        if (first <= 0) return
        const rows = root.model
        const tail = rows.get(last)
        const app = String(tail.appName)
        const day = root.dayKey(tail.time)
        const below = last + 1 < rows.count ? rows.get(last + 1) : null
        if (below && String(below.appName) === app && root.dayKey(below.time) === day) return
        const above = rows.get(first - 1)
        if (String(above.appName) !== app || root.dayKey(above.time) !== day) return
        if (root._openRuns[root.runKey(app, day, tail)] === true) root._tailHeir = first - 1
    }

    function _carryRemovedTail(): void {
        const heir = root._tailHeir
        if (heir < 0) return
        root._tailHeir = -1
        root.setOpen(root.runBounds(heir).key, true)
    }

    // A removed or shortened tail must not leave its key behind for a later
    // group that happens to carry the same app, id, time, and day.
    function _pruneOpenRuns(): void {
        const rows = root.model
        const runs = []
        for (let i = 0; i < rows.count; i++) {
            const row = rows.get(i)
            const app = String(row.appName)
            const day = root.dayKey(row.time)
            const last = runs[runs.length - 1]
            if (last && last.app === app && last.day === day) {
                last.length++
                last.tail = row
            } else {
                runs.push({ app: app, day: day, length: 1, tail: row })
            }
        }

        const keep = {}
        for (let i = 0; i < runs.length; i++) {
            const run = runs[i]
            if (run.length < root.foldAt) continue
            const key = root.runKey(run.app, run.day, run.tail)
            if (root._openRuns[key] === true) keep[key] = true
        }

        let same = true
        for (const key in root._openRuns) {
            if (!keep[key]) {
                same = false
                break
            }
        }
        if (!same) root._openRuns = keep
    }

    property Connections _modelChanges: Connections {
        target: root.model
        function onRowsAboutToBeInserted() { root.modelAboutToChange() }
        // before onCountChanged, whose prune drops the old tail's key
        function onRowsInserted(parent, first: int, last: int) { root._carryOpenTail(first, last) }
        function onRowsAboutToBeRemoved(parent, first: int, last: int) {
            root.modelAboutToChange()
            root._noteRemovedTail(first, last)
        }
        function onModelAboutToBeReset() { root.modelAboutToChange() }
        // not on rowsRemoved: a carry there can reach the list's rows before they are
        // renumbered, and the last one reads past the shortened model
        function onCountChanged() {
            root._carryRemovedTail()
            root._pruneOpenRuns()
        }
    }
}
