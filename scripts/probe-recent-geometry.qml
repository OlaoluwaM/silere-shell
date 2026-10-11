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
    property real takerTop: -1
    property int takerFrames: 0
    property int cardStrays: 0
    property string cardFirstStray: ""
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
    function headers(): var {
        const list = root.findList(page)
        const out = []
        if (!list) return out
        const label = page.sectionLabel(Date.now())
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
            if (kids[i]._keepsSection === true) leaving = kids[i]
            if (kids[i]._takesSection === true) taker = kids[i]
        }
        if (!taker) return
        root.takerFrames++
        const top = taker.y + taker._gapAbove + taker._sectionHeight - taker._takeLift
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
                console.log("PROBE-RECENT-GEOMETRY " + (root.failures ? "failed" : "passed")
                    + " " + root.checks + " checks")
                console.log("PROBE-RECENT-DONE")
                stop()
                break
            }
            }
        }
    }
}
