import QtQuick

ParallelAnimation {
    id: root

    required property QtObject target
    required property bool entering
    required property real hiddenOffset
    property string opacityProperty: "opacity"
    property string offsetProperty: "edgeOffset"
    // one popup taking another's place hands over in turn: the leaving one goes first, a little
    // slower than an ordinary close so the eye can follow it, and the arriving one waits that out
    // before its ordinary entrance
    property bool swap: false

    readonly property bool _swapExit: root.swap && !root.entering
    readonly property int _wait: root.swap && root.entering ? Motion.medium : 0
    SequentialAnimation {
        PauseAnimation { duration: root._wait }
        NumberAnimation {
            target: root.target
            property: root.offsetProperty
            to: root.entering ? 0.0 : root.hiddenOffset
            duration: root.entering ? Motion.popIn : root._swapExit ? Motion.medium : Motion.popOut
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.entering ? Motion.emphasizedDecel : Motion.emphasizedAccel
        }
    }
    SequentialAnimation {
        PauseAnimation { duration: root._wait }
        NumberAnimation {
            target: root.target
            property: root.opacityProperty
            to: root.entering ? 1.0 : 0.0
            duration: root.entering ? Motion.popInFade : root._swapExit ? Motion.normal : Motion.popOutFade
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.entering ? Motion.standardDecel : Motion.standardAccel
        }
    }
}
