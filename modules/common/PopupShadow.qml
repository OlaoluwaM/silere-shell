pragma ComponentBehavior: Bound

import QtQuick
import "../../services"

Loader {
    id: root

    required property FloatingPopupCard card

    active: (card.open || card.opacity > 0.001) && ShellSettings.barShadow
    anchors.fill: card
    opacity: card.opacity
    z: -1
    // this is a sibling of the card, so transforms are not inherited. Mirror the card's motion or its shadow visibly lags at the final geometry
    transform: Translate { y: root.card.edgeOffset }
    sourceComponent: FloatingShadow {
        radius: root.card.radius
        atBottom: root.card.barBottom
    }
}
