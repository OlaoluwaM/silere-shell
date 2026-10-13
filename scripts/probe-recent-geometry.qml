pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "services"
import "modules/menu" as Menu

// A history row sizes itself from its parts, so a row inserted while the page is shown, or
// while it is hidden and then revealed, must end up starting where the row above ends once
// the motion is over, and a hidden page must already size its rows as the shown one will,
// or every card grows on reveal. The checks read the rows back rather than the list's own
// bookkeeping
ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0
    property bool pageActive: true
    property int phase: 0
    property int nextId: 1
    property real expandedBefore: 0
    property var fullWhileHidden: []
    property real headerY: -1
    property int handoffFrames: 0
    property int handoffStrays: 0
    property string handoffFirstStray: ""
    property var takerRow: null
    property real takerTop: -1
    property int takerFrames: 0
    property int cardStrays: 0
    property string cardFirstStray: ""
    property var tailLeaving: null
    property var tailAbove: null
    property real tailAboveTop: -1
    property int tailFrames: 0
    property int tailClosing: 0
    property int tailStrays: 0
    property string tailFirstStray: ""
    property var quickFirst: null
    property real quickLeastK: 1
    property int quickFrames: 0
    property var foldRow: null
    property real foldStart: 0
    property int foldSteps: 0
    property var reuseLeaving: null
    property var reuseAbove: null
    property int reuseSeen: 0
    property int reuseStrays: 0
    property int overlapFrames: 0
    property int overlapStrays: 0
    property string overlapFirstStray: ""
    property var dayTaker: null
    property real dayTakerTop: -1
    property int dayFrames: 0
    property int dayStrays: 0
    property string dayFirstStray: ""
    property bool dayHeaderFixed: true
    property real dayTakerRoom: -1
    readonly property string longBody: "The body wraps over more than two lines at this width so the "
        + "collapsed card truncates it and the disclosure pill has something to reveal when tapped."

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    // a list only creates and lays out its rows inside a window's polish loop, so the page
    // gets a real, if offscreen, one
    FloatingWindow {
        id: host
        visible: true
        implicitWidth: 400
        implicitHeight: 520
        color: "transparent"
        Menu.RecentPage {
            id: page
            // the menu's loader gives the page its height; without one the list has no room for rows
            height: 520
            viewportHeight: 520
            active: root.pageActive
            powerOpen: false
            animateOnCreate: false
        }
    }

    function insert(app: string, body: string): void {
        Notifications.historyModel.insert(0, Notifications._normalizeEntry({
            id: root.nextId++, appName: app, appIcon: "", desktopEntry: "",
            summary: "Summary from " + app, body: body, urgency: 1, time: Date.now(),
            sessionCurrent: true
        }))
    }

    // history files older rows below newer ones, so a row dated days back joins the end
    function appendOld(app: string, daysAgo: int): void {
        const now = new Date()
        Notifications.historyModel.append(Notifications._normalizeEntry({
            id: root.nextId++, appName: app, appIcon: "", desktopEntry: "",
            summary: "Summary from " + app, body: root.longBody, urgency: 1,
            time: new Date(now.getFullYear(), now.getMonth(), now.getDate() - daysAgo, 12).getTime(),
            sessionCurrent: true
        }))
    }

    // the list rests at its end with its last row's bottom on the view's bottom edge
    function atEnd(label: string): void {
        const list = root.findList(page)
        const last = list.itemAtIndex(Notifications.historyCount - 1)
        root.check(list.atYEnd && last !== null
                && Math.abs(last.y + last.height - list.contentY - list.height) < 0.5,
            label + ": the list rests at its end (contentY " + list.contentY + ", last row ends "
                + (last ? last.y + last.height - list.contentY : "unbuilt") + " in a view of "
                + list.height + ")")
    }

    function findList(item): var {
        if (!item) return null
        if (item.contentItem !== undefined && item.delegate !== undefined && item.model !== undefined) return item
        for (let i = 0; i < item.children.length; i++) {
            const found = root.findList(item.children[i])
            if (found) return found
        }
        return null
    }

    function findBody(item): var {
        if (!item) return null
        if (item.bodyText !== undefined && item.expanded !== undefined) return item
        for (let i = 0; i < item.children.length; i++) {
            const found = root.findBody(item.children[i])
            if (found) return found
        }
        return null
    }

    // live rows, top to bottom; pooled rows keep index -1 and folded rows have no height
    function rows(): var {
        const list = root.findList(page)
        const out = []
        if (!list) return out
        const kids = list.contentItem.children
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            if (c.index === undefined || c.index < 0 || c.height <= 0) continue
            out.push(c)
        }
        out.sort((a, b) => a.y - b.y)
        return out
    }

    // every drawn day header under the list, wherever it sits, with the opacity it is drawn at
    function headers(day): var {
        const list = root.findList(page)
        const out = []
        if (!list) return out
        const label = page.sectionLabel(day || Date.now())
        const visit = item => {
            if (!item || !item.visible) return
            if (item.text === label && item.font !== undefined) {
                let alpha = 1
                for (let p = item; p && p !== list; p = p.parent) alpha *= p.opacity
                if (alpha > 0.01) out.push({ y: item.mapToItem(list, 0, 0).y, alpha: alpha })
                return
            }
            for (let i = 0; i < item.children.length; i++) visit(item.children[i])
        }
        visit(list.contentItem)
        return out
    }

    // removing the first row under a day hands its header to the next row of that day, so on
    // every frame of the removal exactly one header is drawn, and it never leaves its place
    FrameAnimation {
        id: _handoffWatch
        running: false
        onTriggered: {
            const drawn = root.headers()
            root.handoffFrames++
            root.cardsFollow()
            const ok = drawn.length === 1 && Math.abs(drawn[0].y - root.headerY) < 0.5
            if (ok) return
            root.handoffStrays++
            if (root.handoffFirstStray.length === 0)
                root.handoffFirstStray = "frame " + root.handoffFrames + ": "
                    + JSON.stringify(drawn) + " against y " + root.headerY
        }
    }

    // and the next card rises under the header without a jump and without running into the
    // card that is leaving
    function cardsFollow(): void {
        const list = root.findList(page)
        if (!list) return
        let leaving = null
        let taker = null
        const kids = list.contentItem.children
        for (let i = 0; i < kids.length; i++) {
            if (kids[i]._handingOff === true) leaving = kids[i]
            if (kids[i]._takesSection === true) taker = kids[i]
        }
        if (!taker) return
        root.takerFrames++
        // a second clear under the header hands it on to the row below, whose card starts lower
        if (taker !== root.takerRow) root.takerTop = -1
        root.takerRow = taker
        const top = taker.y + taker._topRoom
        let stray = ""
        if (root.takerTop >= 0 && top > root.takerTop + 0.5)
            stray = "the next card moved down from " + root.takerTop + " to " + top
        else if (leaving && top < leaving.y + leaving.height - 0.5)
            stray = "the next card at " + top + " ran into the leaving card ending at "
                + (leaving.y + leaving.height)
        root.takerTop = top
        if (stray.length === 0) return
        root.cardStrays++
        if (root.cardFirstStray.length === 0)
            root.cardFirstStray = "frame " + root.handoffFrames + ": " + stray
    }

    // a list scrolled to its end that loses its last row keeps that row in view while it
    // closes, rather than snapping up to the new end and closing it below the view, and the
    // rows above only ever move down to fill its room
    FrameAnimation {
        id: _tailWatch
        running: false
        onTriggered: {
            const list = root.findList(page)
            const leaving = root.tailLeaving
            const above = root.tailAbove
            root.tailFrames++
            if (leaving.height > 0.5 && leaving.height < leaving._fullHeight - 0.5) root.tailClosing++
            const top = leaving.y - list.contentY
            const aboveTop = above.y - list.contentY
            let stray = ""
            if (leaving.height > 0.5 && (top < -0.5 || top + leaving.height > list.height + 0.5))
                stray = "the leaving row spans " + top + " to " + (top + leaving.height)
                    + " outside a view of " + list.height
            else if (root.tailAboveTop >= 0 && aboveTop < root.tailAboveTop - 0.5)
                stray = "the row above moved up from " + root.tailAboveTop + " to " + aboveTop
            root.tailAboveTop = aboveTop
            if (stray.length === 0) return
            root.tailStrays++
            if (root.tailFirstStray.length === 0)
                root.tailFirstStray = "frame " + root.tailFrames + ": " + stray
        }
    }

    // a second clear while the first row is still closing must not cut the first one short
    FrameAnimation {
        id: _quickWatch
        running: false
        onTriggered: {
            root.quickFrames++
            if (root.quickFirst._leaving) root.quickLeastK = Math.min(root.quickLeastK, root.quickFirst._leaveK)
            if (root.quickFrames !== 3) return
            const list = root.findList(page)
            const next = list.itemAtIndex(Notifications.historyCount - 1)
            if (next) next.removeSelf()
        }
    }

    // a run that a removal folds into the run above closes on the leaving row's curve
    FrameAnimation {
        id: _foldWatch
        running: false
        onTriggered: {
            const h = root.foldRow.height
            if (h > 0.5 && h < root.foldStart - 0.5) root.foldSteps++
        }
    }

    // a second clear while the first row still closes: the next day head handing the header
    // on from where the first one drew it, and the like
    FrameAnimation {
        id: _chainWatch
        property int frames: 0
        property var act: () => root.findList(page).itemAtIndex(0).removeSelf()
        running: false
        onTriggered: {
            if (++frames !== 3) return
            stop()
            act()
        }
    }

    // back and forth past a page on the first frames of the exit, so every row the list has
    // handed back is built again before the leaving ones could close
    FrameAnimation {
        id: _jumpWatch
        property int frames: 0
        running: false
        onTriggered: {
            const list = root.findList(page)
            if (++frames % 2) list.positionViewAtBeginning()
            else list.positionViewAtEnd()
            if (frames >= 3) stop()
        }
    }

    // every row drawn, leaving or not, starts at or below the end of the one above
    FrameAnimation {
        id: _overlapWatch
        running: false
        onTriggered: {
            const list = root.findList(page)
            const drawn = []
            const kids = list.contentItem.children
            for (let i = 0; i < kids.length; i++) {
                const c = kids[i]
                if (c._leaving !== undefined && !c._pooled && c.visible && c.height > 0.5) drawn.push(c)
            }
            drawn.sort((a, b) => a.y - b.y)
            root.overlapFrames++
            for (let i = 1; i < drawn.length; i++) {
                const above = drawn[i - 1]
                if (drawn[i].y >= above.y + above.height - 0.5) continue
                root.overlapStrays++
                if (root.overlapFirstStray.length === 0)
                    root.overlapFirstStray = "frame " + root.overlapFrames + ": a row at "
                        + drawn[i].y + " starts inside the one above, " + above.y + " to "
                        + (above.y + above.height)
                return
            }
        }
    }

    // a clear under another day must leave today's handoff running: today's header holds
    // still and the card taking it over only rises
    FrameAnimation {
        id: _dayWatch
        running: false
        onTriggered: {
            const drawn = root.headers()
            const top = root.dayTaker.y + root.dayTaker._topRoom
            root.dayFrames++
            const room = root.dayTaker._topRoom
            let stray = ""
            if (drawn.length !== 1
                    || (root.dayHeaderFixed && Math.abs(drawn[0].y - root.headerY) > 0.5))
                stray = "today's header drawn at " + JSON.stringify(drawn) + " against y " + root.headerY
            else if (root.dayHeaderFixed && root.dayTakerTop >= 0 && top > root.dayTakerTop + 0.5)
                stray = "today's next card moved down from " + root.dayTakerTop + " to " + top
            else if (!root.dayHeaderFixed && root.dayTakerRoom >= 0 && room < root.dayTakerRoom - 0.5)
                stray = "the header's room under the next card shut from " + root.dayTakerRoom
                    + " to " + room
            root.dayTakerTop = top
            root.dayTakerRoom = room
            if (stray.length === 0) return
            root.dayStrays++
            if (root.dayFirstStray.length === 0) root.dayFirstStray = "frame " + root.dayFrames + ": " + stray
        }
    }

    // a leaving row follows the row above it only while that row stands there: once the list
    // takes it back for another entry, following it would carry the leaving row away
    FrameAnimation {
        id: _reuseWatch
        running: false
        onTriggered: {
            const above = root.reuseAbove
            if (!root.reuseLeaving._leaving || (!above._pooled && above.index === 2)) return
            root.reuseSeen++
            if (root.reuseLeaving._after === above) root.reuseStrays++
        }
    }

    function resetHandoff(): void {
        root.headerY = -1
        const before = root.headers()
        if (before.length === 1) root.headerY = before[0].y
        root.handoffFrames = 0
        root.handoffStrays = 0
        root.handoffFirstStray = ""
        root.takerRow = null
        root.takerTop = -1
        root.takerFrames = 0
        root.cardStrays = 0
        root.cardFirstStray = ""
    }

    function handoffHeld(label: string): void {
        root.check(root.takerFrames >= 5, label + ": the next row was seen taking the header over on "
            + root.takerFrames + " frames")
        root.check(root.cardStrays === 0, label + ": the next card follows the leaving ones up ("
            + root.cardStrays + " stray frames; " + root.cardFirstStray + ")")
        root.check(root.handoffStrays === 0, label + ": the day header holds still ("
            + root.handoffStrays + " stray frames; " + root.handoffFirstStray + ")")
    }

    // the size a row aims for is its own sum, which a reveal must not change: a row sized
    // smaller while hidden animates up to its real height every time the page is shown
    function recordHidden(): void {
        root.fullWhileHidden = root.rows().map(r => r._fullHeight)
    }

    function sizedWhileHidden(label: string): void {
        const live = root.rows()
        root.check(live.length === root.fullWhileHidden.length,
            label + ": the rows seen while hidden are the rows that settled")
        for (let i = 0; i < live.length && i < root.fullWhileHidden.length; i++)
            root.check(live[i]._fullHeight === root.fullWhileHidden[i],
                label + ": row " + i + " aimed at " + root.fullWhileHidden[i]
                    + " while hidden but settled at " + live[i]._fullHeight)
    }

    function settled(label: string, expected: int): void {
        const live = root.rows()
        const list = root.findList(page)
        root.check(live.length === expected,
            label + ": " + expected + " rows are live, saw " + live.length + " (history "
                + Notifications.historyCount + ", list " + (list ? list.count + " x " + list.width
                + "x" + list.height : "missing") + ", page " + page.width + "x" + page.height + ")")
        for (let i = 0; i < live.length; i++) {
            const r = live[i]
            root.check(Math.abs(r.height - (r._fullHeight + r._peekStep * r._peeks)) < 0.5,
                label + ": row " + i + " height " + r.height + " is its own full height "
                    + (r._fullHeight + r._peekStep * r._peeks))
            if (i === 0) continue
            const above = live[i - 1]
            root.check(r.y >= above.y + above.height - 0.5,
                label + ": row " + i + " at y " + r.y + " starts past the row above ending at "
                    + (above.y + above.height))
        }
    }

    // the list hands a row it took back mid-exit to another entry, which must stand fully
    // open and free to leave; a row that closed on its old exit has no height, so rows()
    // would pass it by
    function allOpen(label: string): void {
        const kids = root.findList(page).contentItem.children
        let live = 0
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            if (c._leaving === undefined || c._pooled || c._leaving || c.index < 0) continue
            live++
            root.check(c._leaveK === 1 && c._leaveFade === 1,
                label + ": row " + c.index + " stands open (closed to " + c._leaveK
                    + ", faded to " + c._leaveFade + ")")
            // the list keeps a row whose delayRemove is set, once its entry is removed, for good
            root.check(!c.ListView.delayRemove, label + ": row " + c.index + " is not held back "
                + "from a later removal")
        }
        root.check(live > 0, label + ": rows are live")
    }

    Timer {
        id: _ticks
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            switch (root.phase++) {
            case 1:
                root.insert("Alpha", "")
                root.insert("Beta", root.longBody)
                root.insert("Gamma", root.longBody)
                break
            case 7: {
                root.settled("seeded", 3)
                const live = root.rows()
                if (live.length === 3)
                    root.check(live[0].height - live[2].height >= 14,
                        "a wrapped body makes its row taller than a body-less row")
                root.insert("Delta", root.longBody)
                break
            }
            case 13:
                root.settled("inserted while shown", 4)
                root.pageActive = false
                page.settleVisual(false)
                root.check(!page.visible, "an inactive page is hidden")
                root.insert("Epsilon", root.longBody)
                break
            case 14:
                root.recordHidden()
                break
            case 15:
                root.pageActive = true
                page.settleVisual(true)
                break
            case 21: {
                root.settled("inserted while hidden, then revealed", 5)
                root.sizedWhileHidden("inserted while hidden, then revealed")
                const live = root.rows()
                const body = live.length > 0 ? root.findBody(live[0]) : null
                root.check(body !== null && body.truncated, "the newest row's body is truncated")
                if (body) {
                    root.expandedBefore = live[0].height
                    body.toggle()
                }
                break
            }
            case 27: {
                root.settled("expanded", 5)
                const live = root.rows()
                root.check(live.length > 0 && live[0].height > root.expandedBefore + 10,
                    "expanding a body grows its row")
                ShellSettings.reduceMotion = true
                root.pageActive = false
                page.settleVisual(false)
                root.insert("Zeta", root.longBody)
                break
            }
            case 28:
                root.recordHidden()
                break
            case 29:
                root.pageActive = true
                page.settleVisual(true)
                break
            case 33:
                root.settled("revealed under reduced motion", 6)
                root.sizedWhileHidden("revealed under reduced motion")
                ShellSettings.reduceMotion = false
                break
            case 35: {
                const before = root.headers()
                root.check(before.length === 1, "one day header before the removal, saw "
                    + JSON.stringify(before))
                root.headerY = before.length > 0 ? before[0].y : -1
                const live = root.rows()
                if (live.length > 0) {
                    _handoffWatch.start()
                    live[0].removeSelf()
                }
                break
            }
            case 39: {
                _handoffWatch.stop()
                root.check(root.handoffFrames >= 5, "the removal was sampled over "
                    + root.handoffFrames + " frames")
                root.check(root.takerFrames >= 5, "the next row was seen taking the header over on "
                    + root.takerFrames + " frames")
                root.check(root.cardStrays === 0, "the next card follows the leaving one up ("
                    + root.cardStrays + " stray frames; " + root.cardFirstStray + ")")
                root.check(root.handoffStrays === 0, "the day header holds still while the "
                    + "next row takes it over (" + root.handoffStrays + " stray frames; "
                    + root.handoffFirstStray + ")")
                root.settled("after the header handoff", 5)
                const after = root.headers()
                root.check(after.length === 1 && Math.abs(after[0].y - root.headerY) < 0.5,
                    "the next row draws the header where it was")
                for (const app of ["Eta", "Theta", "Iota", "Kappa", "Lambda", "Mu", "Nu", "Xi"])
                    root.insert(app, root.longBody)
                break
            }
            case 45:
                root.findList(page).positionViewAtEnd()
                break
            case 47: {
                const list = root.findList(page)
                const last = Notifications.historyCount - 1
                root.check(list.contentHeight > list.height && list.atYEnd,
                    "the list overflows and sits at its end before its last row leaves")
                root.tailLeaving = list.itemAtIndex(last)
                root.tailAbove = list.itemAtIndex(last - 1)
                if (root.tailLeaving && root.tailAbove) {
                    _tailWatch.start()
                    root.tailLeaving.removeSelf()
                }
                break
            }
            case 52: {
                _tailWatch.stop()
                const list = root.findList(page)
                root.check(root.tailClosing >= 5, "the last row was seen closing on "
                    + root.tailClosing + " frames")
                root.check(root.tailStrays === 0, "the last row closes in view while the rows "
                    + "above follow it down (" + root.tailStrays + " stray frames; "
                    + root.tailFirstStray + ")")
                root.atEnd("after the last row leaves at the end")
                // a scrolled list builds only the rows near the view, so the rows it has are the set
                root.settled("after the last row leaves at the end", root.rows().length)
                root.appendOld("Omicron", 1)
                root.appendOld("Pi", 1)
                break
            }
            case 54:
                root.findList(page).positionViewAtEnd()
                break
            case 56: {
                // the first row under the last day hands its header to the row after it, so the
                // list gives up less room than the leaving row's height
                const list = root.findList(page)
                const first = list.itemAtIndex(Notifications.historyCount - 2)
                root.check(first !== null && first._showSection,
                    "the last day's first row carries its header before it leaves")
                if (first) first.removeSelf()
                break
            }
            case 61: {
                root.atEnd("after the last day's first row leaves")
                // history replaces a row in place when its sender updates it, a removal and an
                // insert in one pass that leave the content as it was
                const list = root.findList(page)
                root.tailAboveTop = list.contentY
                const last = Notifications.historyCount - 1
                const entry = Notifications.historyModel.get(last)
                const copy = {}
                for (const role of ["id", "appName", "appIcon", "desktopEntry", "summary", "body",
                        "urgency", "time", "sessionCurrent"])
                    copy[role] = entry[role]
                Notifications.historyModel.remove(last)
                Notifications._prependHistory(copy)
                break
            }
            case 66: {
                const list = root.findList(page)
                root.check(Math.abs(list.contentY - root.tailAboveTop) < 0.5,
                    "a row replaced in place leaves the view where it was (contentY "
                        + root.tailAboveTop + " to " + list.contentY + ")")
                root.atEnd("after a row is replaced in place")
                root.quickFirst = list.itemAtIndex(Notifications.historyCount - 1)
                _quickWatch.start()
                root.quickFirst.removeSelf()
                break
            }
            case 71: {
                _quickWatch.stop()
                root.check(root.quickLeastK < 0.01, "the first of two quick clears closes all the "
                    + "way (it stopped at " + root.quickLeastK + ")")
                root.atEnd("after two quick clears")
                // a full history drops its oldest row as a new one arrives, here the last row
                const list = root.findList(page)
                const last = Notifications.historyCount - 1
                root.tailLeaving = list.itemAtIndex(last)
                root.tailAbove = list.itemAtIndex(last - 1)
                root.tailAboveTop = -1
                root.tailFrames = 0
                root.tailClosing = 0
                root.tailStrays = 0
                root.tailFirstStray = ""
                ShellSettings.notifHistoryLimit = Notifications.historyCount
                _tailWatch.start()
                root.insert("Rho", "")
                Notifications._trimHistory()
                break
            }
            case 76: {
                _tailWatch.stop()
                root.check(root.tailClosing >= 5, "the trimmed row was seen closing on "
                    + root.tailClosing + " frames")
                root.check(root.tailStrays === 0, "the trimmed row closes in view while the rows "
                    + "above follow it down (" + root.tailStrays + " stray frames; "
                    + root.tailFirstStray + ")")
                root.atEnd("after the oldest row is trimmed")
                ShellSettings.notifHistoryLimit = 100
                for (const app of ["Sigma", "Sigma", "Sigma", "Tau", "Sigma", "Sigma", "Sigma"])
                    root.appendOld(app, 3)
                break
            }
            case 78:
                root.findList(page).positionViewAtEnd()
                break
            case 80: {
                // removing the row between two runs of one app joins them, and the lower one folds
                const list = root.findList(page)
                const count = Notifications.historyCount
                const between = list.itemAtIndex(count - 4)
                root.foldRow = list.itemAtIndex(count - 3)
                root.check(between !== null && between.modelData.appName === "Tau"
                        && root.foldRow !== null && root.foldRow._stacked,
                    "two folded runs of one app stand either side of another app's row")
                if (!between || !root.foldRow) break
                root.foldStart = root.foldRow.height
                _foldWatch.start()
                between.removeSelf()
                break
            }
            case 85: {
                _foldWatch.stop()
                root.check(root.foldSteps >= 3, "the joined run folds over " + root.foldSteps
                    + " frames rather than at once")
                root.atEnd("after two runs join")
                // a reload, or history turned off, empties the model outside Clear all, so
                // every built row leaves at once
                Notifications.historyModel.clear()
                for (const app of ["Phi", "Chi", "Psi", "Upsilon", "Upsilon", "Upsilon"])
                    root.insert(app, "")
                break
            }
            case 87:
                root.findList(page).positionViewAtBeginning()
                root.findList(page).itemAtIndex(0)._toggleExpand()
                break
            case 90: {
                // an open run's Clear all takes every row of it at once, all above the taker
                const list = root.findList(page)
                const head = list.itemAtIndex(0)
                root.check(head._runOpen && list.itemAtIndex(2).height > 0,
                    "the day's first run stands open before it is cleared")
                root.resetHandoff()
                root.check(root.headerY >= 0, "one day header before the open run is cleared")
                _handoffWatch.start()
                head.removeRun()
                break
            }
            case 94:
                _handoffWatch.stop()
                root.handoffHeld("an open run cleared")
                root.resetHandoff()
                _handoffWatch.start()
                _chainWatch.start()
                root.findList(page).itemAtIndex(0).removeSelf()
                break
            case 99:
                _handoffWatch.stop()
                root.handoffHeld("two day heads cleared in quick succession")
                root.settled("after two day heads leave", 1)
                root.insert("Omega", "")
                break
            case 101:
                // reduced motion closes a row before the removal returns
                ShellSettings.reduceMotion = true
                root.findList(page).itemAtIndex(0).removeSelf()
                break
            case 102:
                root.check(page._leavingRows.length === 0, "a row that closes at once is not "
                    + "left among the leaving ones (" + page._leavingRows.length + ")")
                root.insert("Omega", "")
                break
            case 104: {
                ShellSettings.reduceMotion = false
                const row = root.findList(page).itemAtIndex(0)
                row.removeSelf()
                root.check(row._leaving && row._after !== row,
                    "a reused row leaving again does not follow itself")
                break
            }
            case 107:
                root.check(page._leavingRows.length === 0, "every leaving row is let go once "
                    + "it closes (" + page._leavingRows.length + ")")
                for (let i = 0; i < 30; i++) root.insert("Row " + i, root.longBody)
                break
            case 109:
                root.findList(page).positionViewAtBeginning()
                break
            case 111: {
                const list = root.findList(page)
                root.reuseAbove = list.itemAtIndex(2)
                root.reuseLeaving = list.itemAtIndex(3)
                _reuseWatch.start()
                root.reuseLeaving.removeSelf()
                // just past the list's cache: a jump clear of every built row lets them all go
                list.contentY = root.reuseAbove.y + root.reuseAbove.height + list.cacheBuffer + 20
                break
            }
            case 114:
                _reuseWatch.stop()
                root.check(root.reuseSeen > 0, "the row above a leaving one was taken back "
                    + "while it closed")
                root.check(root.reuseStrays === 0, "a leaving row stops following a row the "
                    + "list has taken back (" + root.reuseStrays + " frames)")
                Notifications.historyModel.clear()
                root.insert("Kappa", "")
                for (let i = 0; i < 4; i++) root.insert("Lambda", "")
                break
            case 116:
                root.findList(page).positionViewAtBeginning()
                root.findList(page).itemAtIndex(0)._toggleExpand()
                break
            case 119: {
                // a row cleared from an open run, then the run's Clear all while it still closes
                const list = root.findList(page)
                root.check(list.itemAtIndex(0)._runOpen && list.itemAtIndex(1).height > 0,
                    "the run stands open before a row of it is cleared")
                _overlapWatch.start()
                list.itemAtIndex(1).removeSelf()
                _chainWatch.frames = 0
                _chainWatch.act = () => root.findList(page).itemAtIndex(0).removeRun()
                _chainWatch.start()
                break
            }
            case 124:
                _overlapWatch.stop()
                root.check(root.overlapFrames >= 5, "the run clear was sampled over "
                    + root.overlapFrames + " frames")
                root.check(root.overlapStrays === 0, "a row still closing inside a cleared run keeps "
                    + "its place among the run's rows (" + root.overlapStrays + " stray frames; "
                    + root.overlapFirstStray + ")")
                root.settled("after a run is cleared around a closing row", 1)
                Notifications.historyModel.clear()
                root.insert("Tb", "")
                root.insert("Ta", "")
                root.appendOld("Ya", 1)
                root.appendOld("Yb", 1)
                break
            case 126:
                root.findList(page).positionViewAtBeginning()
                break
            case 128: {
                // today's head cleared, then yesterday's while today's still closes
                const list = root.findList(page)
                const yesterday = Notifications.historyModel.get(2).time
                root.check(root.headers().length === 1 && root.headers(yesterday).length === 1,
                    "today and yesterday each draw one header before their heads are cleared")
                root.resetHandoff()
                root.dayTaker = list.itemAtIndex(1)
                _dayWatch.start()
                list.itemAtIndex(0).removeSelf()
                _chainWatch.frames = 0
                _chainWatch.act = () => root.findList(page).itemAtIndex(1).removeSelf()
                _chainWatch.start()
                break
            }
            case 133:
                _dayWatch.stop()
                root.check(root.dayFrames >= 5, "the two clears were sampled over " + root.dayFrames
                    + " frames")
                root.check(root.dayStrays === 0, "a clear under another day leaves today's handoff "
                    + "running (" + root.dayStrays + " stray frames; " + root.dayFirstStray + ")")
                root.settled("after heads under two days leave", 2)
                for (const app of ["Rho", "Sigma", "Tau"]) root.insert(app, "")
                break
            case 135: {
                // the head cleared, a new one arriving, and that one cleared too while the first
                // still closes: both hand today's header to the same row
                const list = root.findList(page)
                list.positionViewAtBeginning()
                list.itemAtIndex(0).removeSelf()
                _chainWatch.frames = 0
                _chainWatch.act = () => root.insert("Upsilon", "")
                _chainWatch.start()
                break
            }
            case 136: {
                // the header sits on the arrival, which still follows the closing head up, and
                // the list re-places its rows for a frame when it lets that head go, so what
                // holds here is the room: it only opens, on the later exit's clock
                const list = root.findList(page)
                root.dayTaker = list.itemAtIndex(1)
                root.dayTakerTop = -1
                root.dayTakerRoom = -1
                root.dayFrames = 0
                root.dayStrays = 0
                root.dayFirstStray = ""
                root.dayHeaderFixed = false
                _dayWatch.start()
                list.itemAtIndex(0).removeSelf()
                break
            }
            case 140:
                _dayWatch.stop()
                root.check(root.dayFrames >= 5, "the second head's exit was sampled over "
                    + root.dayFrames + " frames")
                root.check(root.dayStrays === 0, "a row handed one header twice opens its room "
                    + "on one clock (" + root.dayStrays + " stray frames; " + root.dayFirstStray + ")")
                root.settled("after two heads leave around an arrival", 4)
                for (let i = 0; i < 8; i++) root.insert("Fold", "")
                for (let i = 0; i < 30; i++) root.insert("Row " + i, root.longBody)
                break
            case 142:
                root.findList(page).positionViewAtEnd()
                break
            case 144: {
                // a jump past a page hands every built row back, the leaving ones too, and the
                // rows at the other end are built from them while they would still be closing
                const list = root.findList(page)
                const stack = list.itemAtIndex(30)
                root.check(stack !== null && stack._stacked && stack._runLength === 8,
                    "a folded run of eight stands in view before it is cleared")
                if (!stack) break
                stack.removeSelf()
                list.positionViewAtEnd()
                _jumpWatch.start()
                break
            }
            case 148:
                root.allOpen("after jumps take a cleared run back mid-exit")
                console.log("PROBE-RECENT-GEOMETRY " + (root.failures ? "failed" : "passed")
                    + " " + root.checks + " checks")
                console.log("PROBE-RECENT-DONE")
                stop()
                break
            }
        }
    }
}
