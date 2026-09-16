import QtQuick

ParallelAnimation {
    id: root

    required property QtObject target
    required property bool entering
    required property real hiddenOffset
    property string opacityProperty: "opacity"
    property string offsetProperty: "edgeOffset"

    NumberAnimation {
        target: root.target
        property: root.offsetProperty
        to: root.entering ? 0.0 : root.hiddenOffset
        duration: root.entering ? Motion.popIn : Motion.popOut
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.entering ? Motion.emphasizedDecel : Motion.emphasizedAccel
    }
    NumberAnimation {
        target: root.target
        property: root.opacityProperty
        to: root.entering ? 1.0 : 0.0
        duration: root.entering ? Motion.popInFade : Motion.popOutFade
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.entering ? Motion.standardDecel : Motion.standardAccel
    }
}
