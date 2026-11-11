pragma ComponentBehavior: Bound

import QtQuick
import "../../services/HistoryRuns.js" as HistoryRuns

// The notification service owns history and labels each row with its run. This object
// owns only the menu's reading of those runs and the expansion state that belongs to them.
QtObject {
    id: root

    required property var model
    property int foldAt: 3
    // the notification service's history category, handed in rather than imported: the
    // singleton would start a notification server inside the grouping probe
    property var log: null
    property var _openRuns: ({})

    // Every built row asks for its shape on each change, and a folded run keeps all of its
    // rows built, so a walk of the run per row grows with the square of its length. The rows
    // are read once per change into a table they all share. No binding observes the table:
    // it is dropped on both sides of a change of rows, and one read while a change is under
    // way is not kept, so a read takes the rows as they stand whichever of this and the list
    // hears of the change first. A relabel moves no row and is reported once it is done;
    // _relabels carries it to the bindings, which read the table rather than the rows
    readonly property var _runs: ({ table: null, changing: false, hearing: null })
    property int _relabels: 0

    // A Connections declared here would connect only as it completes, which comes after
    // the objects made after this one have completed: the list has built its rows by then,
    // they have read their shapes, and a row filed in between would be a change this
    // object never heard of, under a table it kept. Made on demand it connects at once, so
    // the model is heard from the moment it is given, and always before a table is built
    function _hear(): void {
        if (!root._runs.hearing) root._runs.hearing = root._rowChanges.createObject(root)
    }

    // A binding that read the rows itself would come to depend on each one, and Qt
    // notifies those dependencies of a relabel before the model reports it, while the
    // table still holds the old labels. A signal handler records no dependencies
    signal _tableWanted()
    on_TableWanted: {
        root._hear()
        const rows = root.model
        const list = []
        for (let i = 0; i < rows.count; i++) {
            const row = rows.get(i)
            list.push({ appName: row.appName, time: row.time, run: row.run,
                urgency: row.urgency, id: row.id })
        }
        const runOf = []
        let at = 0
        while (at < list.length) {
            let end = at
            while (end + 1 < list.length && HistoryRuns.sameRun(list[end + 1], list[at])) end++
            let critical = false
            for (let i = at; i <= end && !critical; i++)
                critical = Number(list[i].urgency) === 2
            const run = { start: at, end: end, critical: critical }
            for (let i = at; i <= end; i++) runOf.push(run)
            at = end + 1
        }
        root._runs.table = { model: rows, rows: list, runOf: runOf }
    }

    onModelChanged: {
        root._hear()
        root._rowsChanging(false)
    }

    function _table(): var {
        root._relabels
        const runs = root._runs
        if (runs.changing || !runs.table || runs.table.model !== root.model) root._tableWanted()
        const table = runs.table
        if (runs.changing) runs.table = null
        return table
    }

    function _rowsChanging(changing: bool): void {
        root._runs.table = null
        root._runs.changing = changing
    }

    function _trace(...parts): void {
        if (root.log) console.debug(root.log, "grouping:", ...parts)
    }

    // one entry per run, newest first, as the page draws it: app, rows, and whether a
    // run tall enough to stack stands open or folded; a bar marks each day boundary
    function describe(): string {
        const rows = root.model
        if (rows.count === 0) return "(empty)"
        let text = ""
        let at = 0
        while (at < rows.count) {
            const run = root.runBounds(at)
            const state = run.length < root.foldAt ? ""
                : root._openRuns[run.key] === true ? " open" : " folded"
            if (at > 0) text += root.dayKey(rows.get(at).time)
                !== root.dayKey(rows.get(at - 1).time) ? " | " : ", "
            text += rows.get(at).appName + " x" + run.length + state
            at = run.start + run.length
        }
        return text
    }

    function dayKey(ms): string {
        return HistoryRuns.dayKey(ms)
    }

    // The run's label is its identity, so its expansion survives arrivals, a cleared
    // oldest row, and a removal that leaves another run of its app beside it. A row
    // without one (only ever a hand-built model) falls back to its app, day and oldest row
    function runKey(row, tail): string {
        if (row.run) return "run:" + String(row.run)
        return JSON.stringify([String(row.appName), root.dayKey(row.time), tail.id, tail.time])
    }

    function runBounds(index: int): var {
        const rows = root.model
        const n = rows.count
        if (index < 0 || index >= n) return { start: index, length: 1, critical: false, key: "" }

        const table = root._table()
        const run = table.runOf[index]
        return { start: run.start, length: run.end - run.start + 1, critical: run.critical,
            key: root.runKey(table.rows[index], table.rows[run.end]) }
    }

    // A pooled row keeps its last index, and a Binding's value still evaluates while
    // its when is false, so a shortened history is asked for rows it no longer has
    function shapeAt(index: int): var {
        const rows = root.model
        if (index < 0 || index >= rows.count)
            return { first: index === 0, section: true, header: true,
                length: 1, critical: false, key: "", open: false }
        const table = root._table()
        const row = table.rows[index]
        const previous = index > 0 ? table.rows[index - 1] : null
        const section = !previous || root.dayKey(row.time) !== root.dayKey(previous.time)
        // a run of the same app right under another starts with its own header, so its
        // stack and its Clear take only its own rows
        const header = section || !HistoryRuns.sameRun(previous, row)
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
        root._trace(open ? "opened" : "closed", key)
        root._openRuns = next
    }

    function reset(): void {
        root._trace("folded every run")
        root._openRuns = ({})
    }

    // A run that is gone, or too short to stack, gives up its open state, so it comes
    // back folded should it grow into a stack again
    function _pruneOpenRuns(): void {
        const rows = root.model
        const keep = {}
        let at = 0
        while (at < rows.count) {
            const run = root.runBounds(at)
            if (run.length >= root.foldAt && root._openRuns[run.key] === true) keep[run.key] = true
            at = run.start + run.length
        }

        const dropped = []
        for (const key in root._openRuns)
            if (!keep[key]) dropped.push(key)
        if (dropped.length === 0) return
        root._trace("pruned", dropped.join(", "))
        root._openRuns = keep
    }

    property Component _rowChanges: Component {
        Connections {
            target: root.model
            function onRowsAboutToBeInserted() { root._rowsChanging(true) }
            function onRowsInserted() { root._rowsChanging(false) }
            function onRowsAboutToBeRemoved() { root._rowsChanging(true) }
            function onRowsRemoved() { root._rowsChanging(false) }
            function onRowsAboutToBeMoved() { root._rowsChanging(true) }
            function onRowsMoved() { root._rowsChanging(false) }
            function onModelAboutToBeReset() { root._rowsChanging(true) }
            function onModelReset() { root._rowsChanging(false) }
            function onLayoutAboutToBeChanged() { root._rowsChanging(true) }
            function onLayoutChanged() { root._rowsChanging(false) }
            function onDataChanged() {
                root._runs.table = null
                root._relabels++
            }
        }
    }

    property Connections _modelChanges: Connections {
        target: root.model
        function onCountChanged() { root._pruneOpenRuns() }
    }
}
