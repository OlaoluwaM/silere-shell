import QtQuick
import "../../services"

// The wheel ownership behind every shell scroller that can sit inside a scrolling page.
// Qt hands a wheel event a Flickable cannot use, as at its end, on to the Flickable
// around it, so a nested scroller that ran out would scroll the page under it. Here a
// gesture that started on the scroller stays with it to the end, and a gesture already
// scrolling the page passes straight over it: toPage goes true for that event, and the
// scroller drops interactive while it is. A top-level scroller, one in a page that cannot
// scroll, and one that scrolls across the page find no page here and behave as Qt's own.
QtObject {
    id: root

    required property Flickable view
    property bool enabled: true
    property bool toPage: false
    // a plain field, so stamping it on every wheel event notifies nothing
    readonly property var _claim: ({ ownedAt: 0 })

    // walked per call, not cached: a Loader can move the scroller, and a page's
    // interactive follows its content
    function inScrollingPage(): bool {
        if (root.view.flickableDirection === Flickable.HorizontalFlick) return false
        for (let p = root.view.parent; p; p = p.parent)
            if (p instanceof Flickable && p.interactive
                    && p.flickableDirection !== Flickable.HorizontalFlick) return true
        return false
    }

    // above the content, so it sees each wheel event before the scroller does
    readonly property MouseArea _ahead: MouseArea {
        parent: root.view
        anchors.fill: parent
        z: 1
        enabled: root.enabled
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => {
            root.toPage = root.inScrollingPage() && !Scroll.wheelBelongsToList(root._claim)
            if (root.toPage) root._rest.restart()
            wheel.accepted = false
        }
    }

    // below the scroller itself (negative z), so Qt reaches it only with a wheel event
    // the scroller declined, the one that would otherwise go on to the page
    readonly property MouseArea _behind: MouseArea {
        parent: root.view
        anchors.fill: parent
        z: -1
        enabled: root.enabled
        acceptedButtons: Qt.NoButton
        onWheel: (wheel) => {
            wheel.accepted = !root.toPage
                && (wheel.angleDelta.y !== 0 || wheel.pixelDelta.y !== 0)
                && root.inScrollingPage()
        }
    }

    // the scroller takes drags again once the page gesture rests
    readonly property Timer _rest: Timer {
        interval: Scroll.pageLatchMs
        onTriggered: root.toPage = false
    }
}
