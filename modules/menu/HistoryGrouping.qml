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

        const here = rows.get(index)
        let start = index
        while (start > 0 && HistoryRuns.sameRun(rows.get(start - 1), here)) start--
        let end = index
        while (end + 1 < n && HistoryRuns.sameRun(rows.get(end + 1), here)) end++

        let critical = false
        for (let i = start; i <= end && !critical; i++)
            critical = Number(rows.get(i).urgency) === 2

        return { start: start, length: end - start + 1, critical: critical,
            key: root.runKey(here, rows.get(end)) }
    }

    // A pooled row keeps its last index, and a Binding's value still evaluates while
    // its when is false, so a shortened history is asked for rows it no longer has
    function shapeAt(index: int): var {
        const rows = root.model
        if (index < 0 || index >= rows.count)
            return { first: index === 0, section: true, header: true,
                length: 1, critical: false, key: "", open: false }
        const row = rows.get(index)
        const previous = index > 0 ? rows.get(index - 1) : null
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

    property Connections _modelChanges: Connections {
        target: root.model
        function onCountChanged() { root._pruneOpenRuns() }
    }
}
