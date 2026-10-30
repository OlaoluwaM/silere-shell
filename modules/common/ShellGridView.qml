import QtQuick
import "../../config"

GridView {
    id: root

    // A grid that may be too short to scroll sets this, not interactive: the grid turns
    // interactive off while a page wheel gesture passes over it
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
}
