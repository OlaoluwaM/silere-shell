.pragma library

// A history run is the rows of one app on one day that arrived together. Each row carries
// its run as a label (`run`) instead of the run being read off adjacency, so clearing the
// row between two runs of one app leaves two runs, in this process and after a restart,
// since the label is saved with the row. Pure functions over the history ListModel, shared
// by the notification service, which files and labels rows, and the menu's grouping, which
// draws and folds them.

let _serial = 0

function dayKey(ms) {
    const d = new Date(Number(ms || Date.now()))
    return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
}

// the time keeps ids apart across processes, the serial within one
function newRunId() {
    return Date.now().toString(36) + "." + (_serial++).toString(36)
}

function sameAppDay(a, b) {
    return !!a && !!b && String(a.appName) === String(b.appName)
        && dayKey(a.time) === dayKey(b.time)
}

function sameRun(a, b) {
    return sameAppDay(a, b) && String(a.run ?? "") === String(b.run ?? "")
}

// The run a row filed at `at` joins, read before the insert: the older row's below it
// when that is the same app and day, so arrivals in a row stack up; otherwise the newer
// row's above it, as for a notification that closed late and slots in under a run's
// oldest row; otherwise a run of its own
function runForInsert(rows, at, entry) {
    const below = at < rows.count ? rows.get(at) : null
    if (below && below.run && sameAppDay(below, entry)) return String(below.run)
    const above = at > 0 ? rows.get(at - 1) : null
    if (above && above.run && sameAppDay(above, entry)) return String(above.run)
    return newRunId()
}

// A row of another run filed inside a run cuts it in two, read after the insert. The part
// below takes a run of its own, so clearing that row later cannot join the halves again
function splitAt(rows, at) {
    if (at <= 0 || at + 1 >= rows.count) return
    const above = rows.get(at - 1)
    const below = rows.get(at + 1)
    if (!above.run || above.run !== below.run || rows.get(at).run === above.run) return
    const cut = String(below.run)
    const fresh = newRunId()
    for (let i = at + 1; i < rows.count && rows.get(i).run === cut; i++)
        rows.setProperty(i, "run", fresh)
}

// Rows saved before runs were labelled take one by the old adjacency rule, oldest first:
// each joins the run of the same app and day beside it, the older row's below first, then
// a labelled row's above, as when an older shell rewrote a file without the newer rows'
// labels. Labelled rows keep theirs
function labelMissing(rows) {
    for (let i = rows.count - 1; i >= 0; i--) {
        const row = rows.get(i)
        if (row.run) continue
        const below = i + 1 < rows.count ? rows.get(i + 1) : null
        const above = i > 0 ? rows.get(i - 1) : null
        rows.setProperty(i, "run", below && below.run && sameAppDay(below, row) ? String(below.run)
            : above && above.run && sameAppDay(above, row) ? String(above.run)
            : newRunId())
    }
}

// Rows restored under rows filed this session meet at `at`. A row filed before the restore
// landed found no run to join, though the user never separated it from the same app's
// rows saved below it, so the run above the seam takes the run below's label
function joinAt(rows, at) {
    if (at <= 0 || at >= rows.count) return
    const above = rows.get(at - 1)
    const below = rows.get(at)
    if (!above.run || !below.run || above.run === below.run || !sameAppDay(above, below)) return
    const live = String(above.run)
    for (let i = at - 1; i >= 0 && rows.get(i).run === live; i--)
        rows.setProperty(i, "run", String(below.run))
}
