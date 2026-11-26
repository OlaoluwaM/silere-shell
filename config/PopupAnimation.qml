import QtQuick

ParallelAnimation {
    id: root

    required property QtObject target
    required property bool entering
    required property real hiddenOffset
    property string opacityProperty: "opacity"
    property string offsetProperty: "edgeOffset"
    // one popup taking another's place fades through, as the menu's pages do: the leaving one
    // clears where it stands before the arriving one starts, and neither slides
    property bool swap: false

    NumberAnimation {
        target: root.target
        property: root.offsetProperty
        to: root.entering || root.swap ? 0.0 : root.hiddenOffset
        duration: root.swap ? 0 : root.entering ? Motion.popIn : Motion.popOut
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.entering ? Motion.emphasizedDecel : Motion.emphasizedAccel
    }
    SequentialAnimation {
        // the arriving popup waits out the leaving one's fade, so no frame holds both at partial opacity
        PauseAnimation { duration: root.swap && root.entering ? Motion.pageSwapOut : 0 }
        NumberAnimation {
            target: root.target
            property: root.opacityProperty
            to: root.entering ? 1.0 : 0.0
            duration: root.swap ? (root.entering ? Motion.pageSwapIn : Motion.pageSwapOut)
                : root.entering ? Motion.popInFade : Motion.popOutFade
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.entering ? Motion.standardDecel : Motion.standardAccel
        }
    }
}
