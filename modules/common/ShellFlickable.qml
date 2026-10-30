import QtQuick
import "../../config"
import "../../services"

Flickable {
    id: root

    // A nested scroller that may be too short to scroll sets this, not interactive: it
    // turns interactive off while a page wheel gesture passes over it
    property bool scrollable: true
    readonly property NestedWheel _wheel: NestedWheel {
        view: root
        enabled: root.scrollable
    }

    clip: true
    flickDeceleration: Motion.flickDeceleration
    maximumFlickVelocity: Motion.flickVelocity
    // one scroll feel shell-wide: drag stops at the edge, a flick still rebounds
    boundsMovement: Flickable.StopAtBounds
    interactive: scrollable && !_wheel.toPage
    // only a page stamps: a nested scroller still coasting would otherwise hand a fresh
    // gesture on itself to the page
    onContentYChanged: if (!_wheel.inScrollingPage()) Scroll.notePageMoved()
}
