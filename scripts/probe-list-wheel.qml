pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import "services"
import "modules/common"

// A wheel a Flickable cannot use at its end goes on to the Flickable around it, so a
// scroller nested in a scrolling page has to keep its own gesture there, while a gesture
// already scrolling the page still passes over it. Real wheel events, delivered by Qt, so
// the checks cover the delivery order NestedWheel relies on and not only its bookkeeping
ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0
    property int phase: 0
    property int backstopWheels: 0
    property int backstopBefore: 0

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    function wheel(item: Item, dx: int, dy: int): void {
        events.mouseWheel(item, item.width / 2, item.height / 2, Qt.NoButton, Qt.NoModifier, dx, dy, -1)
    }

    // the page and the nested scroller both stand still, and no gesture is under way on either
    function rest(pageY: real, inner: Flickable, innerY: real): void {
        page.cancelFlick()
        inner.cancelFlick()
        page.contentY = pageY
        inner.contentY = innerY
        Scroll._page.movedAt = 0
        inner._wheel._claim.ownedAt = 0
    }

    TestEvent { id: events }

    // a list only creates and lays out its rows inside a window's polish loop
    FloatingWindow {
        id: host
        visible: true
        implicitWidth: 400
        implicitHeight: 300
        color: "transparent"

        // anything no item kept falls through to here, as it would leave the shell's surface
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: (w) => { root.backstopWheels++; w.accepted = true }
        }

        ShellFlickable {
            id: page
            width: 200
            height: 300
            contentWidth: width
            contentHeight: _col.height
            interactive: contentHeight > height

            Column {
                id: _col
                width: page.width

                Item { width: parent.width; height: 100 }

                ShellListView {
                    id: list
                    width: parent.width
                    height: 100
                    scrollable: contentHeight > height
                    model: 20
                    delegate: Item {
                        required property int index
                        width: 200
                        height: 20
                    }
                }

                ShellListView {
                    id: shortList
                    width: parent.width
                    height: Math.min(contentHeight, 100)
                    scrollable: contentHeight > height
                    model: 2
                    delegate: Item {
                        required property int index
                        width: 200
                        height: 20
                    }
                }

                // the shape of a select row's options
                ShellFlickable {
                    id: inner
                    width: parent.width
                    height: 100
                    contentWidth: width
                    contentHeight: 300
                    scrollable: contentHeight > height + 1
                }

                // the shape of the accent swatch row: it scrolls across the page
                ShellFlickable {
                    id: across
                    width: parent.width
                    height: 40
                    contentWidth: 600
                    contentHeight: height
                    flickableDirection: Flickable.HorizontalFlick
                    interactive: contentWidth > width + 1
                }

                Item { width: parent.width; height: 400 }
            }
        }

        ShellListView {
            id: topList
            x: 200
            width: 200
            height: 100
            model: 20
            delegate: Item {
                required property int index
                width: 200
                height: 20
            }
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            switch (root.phase++) {
            case 3:
                root.check(list.scrollable && !shortList.scrollable && list.interactive
                        && inner.scrollable && inner.interactive && page.interactive,
                    "the nested scrollers overflow their height and the short list does not")
                root.rest(0, list, list.contentHeight - list.height)
                root.backstopBefore = root.backstopWheels
                root.wheel(list, 0, -120)
                root.check(!page.flicking && !page.moving,
                    "a list at its end keeps the wheel instead of scrolling the page")
                // something else moving the page meanwhile does not take the gesture off the list
                Scroll.notePageMoved()
                root.wheel(list, 0, -120)
                root.check(!page.flicking && !page.moving && list.interactive,
                    "a gesture that started on the list stays with it while the page moves")
                break
            case 6:
                root.check(page.contentY === 0 && list.atYEnd
                        && root.backstopWheels === root.backstopBefore,
                    "the page is still at its top after the list's end kept the wheel (page "
                        + page.contentY + ")")
                root.rest(50, list, 0)
                root.wheel(list, 0, 120)
                root.check(!page.flicking && !page.moving,
                    "a list at its top keeps an upward wheel from the page")
                break
            case 9:
                root.check(page.contentY === 50,
                    "the page stays where it was under an upward wheel at the list's top (page "
                        + page.contentY + ")")
                root.rest(0, list, 100)
                root.wheel(list, 0, -120)
                root.check(list.moving && !page.moving,
                    "inside its range the list scrolls under the wheel as before")
                break
            case 12:
                root.check(list.contentY > 100 && page.contentY === 0,
                    "the wheel moved the list and not the page (list " + list.contentY
                        + ", page " + page.contentY + ")")
                root.rest(0, list, 100)
                // a gesture that is scrolling the page reaches the list under the pointer
                Scroll.notePageMoved()
                root.wheel(list, 0, -120)
                root.check(!list.interactive && page.moving && !list.moving,
                    "a gesture already scrolling the page passes over the list to the page")
                break
            case 15:
                root.check(page.contentY > 0 && list.contentY === 100,
                    "the page moved and the list held still (page " + page.contentY
                        + ", list " + list.contentY + ")")
                break
            case 18:
                root.check(list.interactive && !list._wheel.toPage,
                    "the list takes drags again once the page gesture rests")
                root.rest(0, list, 0)
                root.wheel(shortList, 0, -120)
                root.check(page.moving,
                    "a list too short to scroll passes the wheel on to the page")
                break
            case 21:
                root.rest(0, list, list.contentHeight - list.height)
                root.backstopBefore = root.backstopWheels
                root.wheel(list, -120, 0)
                root.check(root.backstopWheels === root.backstopBefore + 1,
                    "a sideways wheel the list cannot use still passes it by")
                topList.positionViewAtEnd()
                root.wheel(topList, 0, -120)
                root.check(root.backstopWheels === root.backstopBefore + 2 && !topList._wheel.toPage,
                    "a list with no scrolling page around it lets an unused wheel go, as before")
                break
            case 22:
                // the nested Flickable sits at 240 to 340 in the page; 150 brings it into view
                root.rest(150, inner, 200)
                root.backstopBefore = root.backstopWheels
                root.wheel(inner, 0, -120)
                root.check(!page.moving && root.backstopWheels === root.backstopBefore,
                    "a nested Flickable at its end keeps the wheel instead of scrolling the page")
                break
            case 25:
                root.check(page.contentY === 150 && inner.contentY === 200,
                    "the page stayed put above a nested Flickable at its end (page "
                        + page.contentY + ")")
                root.rest(150, inner, 100)
                root.wheel(inner, 0, -120)
                root.check(inner.moving && !page.moving,
                    "inside its range the nested Flickable scrolls under the wheel")
                break
            case 28:
                root.check(inner.contentY > 100 && page.contentY === 150,
                    "the wheel moved the nested Flickable and not the page (inner "
                        + inner.contentY + ", page " + page.contentY + ")")
                root.rest(150, inner, 100)
                Scroll.notePageMoved()
                root.wheel(inner, 0, -120)
                root.check(!inner.interactive && page.moving && !inner.moving,
                    "a gesture already scrolling the page passes over a nested Flickable")
                break
            case 31:
                root.check(page.contentY > 150 && inner.contentY === 100,
                    "the page moved and the nested Flickable held still (page "
                        + page.contentY + ", inner " + inner.contentY + ")")
                break
            case 34: {
                root.rest(150, inner, 0)
                inner.contentY = 50
                const innerStamped = Scroll._page.movedAt !== 0
                page.contentY = 160
                root.check(!innerStamped && Scroll._page.movedAt !== 0,
                    "only the page counts as the page moving, not a scroller nested in it")
                root.rest(150, across, 0)
                root.wheel(across, 0, -120)
                root.check(page.moving && !across._wheel.toPage && across.interactive,
                    "a wheel down a row that scrolls across the page still scrolls the page")
                break
            }
            case 37:
                root.check(page.contentY > 150,
                    "the page moved under a wheel over the sideways row (page " + page.contentY + ")")
                page.cancelFlick()
                page.contentY = 0
                Scroll._page.movedAt = 0
                // over the page's own lead-in, clear of every nested scroller
                events.mouseWheel(page, 100, 50, Qt.NoButton, Qt.NoModifier, 0, -120, -1)
                root.check(page.moving && page.interactive && !page._wheel.toPage
                        && !page._wheel.inScrollingPage(),
                    "the page itself takes the wheel as before")
                break
            case 40:
                root.check(page.contentY > 0 && Scroll._page.movedAt !== 0,
                    "the page scrolled and stamped its movement as before (page "
                        + page.contentY + ")")
                console.log("PROBE-LIST-WHEEL " + (root.failures ? "failed" : "passed")
                    + " " + root.checks + " checks")
                console.log("PROBE-LIST-WHEEL-DONE")
                stop()
                break
            }
        }
    }
}
