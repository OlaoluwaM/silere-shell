import QtQuick
import "../../../config"

Item {
    id: root

    // SettingsCard still writes these through the rows. The fill no longer reads them: it sits
    // clear of the card's corner arc and border, so it has no card corner to match
    property real  topRadius:    0
    property real  bottomRadius: 0
    property real  cardInset:    1
    property real  leftBleed:    0
    // measured from the card's edge, not the row's: a nested row's bleed pulls the fill back out to it
    property real  insetX:       6
    property real  insetY:       3
    property real  radius:       Theme.radiusInline
    property bool  active:       false
    property bool  pressed:      false
    property real  fillOpacity:  0.08
    property real  pressOpacity: 0.13
    property color fillColor:    Theme.menuHover

    Rectangle {
        x:      -root.leftBleed + root.insetX
        y:      root.insetY
        width:  Math.max(0, parent.width + root.leftBleed - root.insetX * 2)
        height: Math.max(0, parent.height - root.insetY * 2)

        radius:       root.radius
        antialiasing: true

        color: Theme.withAlpha(root.fillColor,
            root.pressed ? Math.max(root.fillOpacity, root.pressOpacity)
                : root.active ? root.fillOpacity : 0)
        ColorFade on color {}
    }
}
