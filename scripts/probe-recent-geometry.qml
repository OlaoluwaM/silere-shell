pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "services"
import "modules/menu" as Menu

// A history row sizes itself from its parts, so a row inserted while the page is shown, or
// while it is hidden and then revealed, must end up starting where the row above ends once
// the motion is over. The checks read the rows back rather than the list's own bookkeeping
ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0
    property bool pageActive: true
    property int phase: 0
    property int nextId: 1
    property real expandedBefore: 0
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
            case 15:
                root.pageActive = true
                page.settleVisual(true)
                break
            case 21: {
                root.settled("inserted while hidden, then revealed", 5)
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
            case 29:
                root.pageActive = true
                page.settleVisual(true)
                break
            case 33:
                root.settled("revealed under reduced motion", 6)
                console.log("PROBE-RECENT-GEOMETRY " + (root.failures ? "failed" : "passed")
                    + " " + root.checks + " checks")
                console.log("PROBE-RECENT-DONE")
                stop()
                break
            }
        }
    }
}
