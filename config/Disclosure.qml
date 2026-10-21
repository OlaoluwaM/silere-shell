import QtQuick

MotionBehavior {
    id: root

    property real closedValue: 0
    property int enterEasing: Easing.BezierSpline
    property int exitEasing: Easing.BezierSpline
    // a list opening from a chevron eases on the standard curve and Motion's list clock; the
    // emphasized pair front-loads its travel, which reads as a snap on a short list
    property bool list: false
    property var enterCurve: root.list ? Motion.standard : Motion.emphasizedDecel
    property var exitCurve: root.list ? Motion.standardAccel : Motion.emphasizedAccel
    // a mutually-exclusive pair must share one curve in both directions, or the
    // expanding sibling outruns the collapsing one and their summed height bulges
    property bool symmetric: false
    readonly property bool _enter: root.symmetric || Math.abs(root.targetValue - root.closedValue) > 1e-6
    property bool _geometryReady: false
    property Timer _geometrySettle: Timer {
        interval: 0
        onTriggered: root._geometryReady = true
    }

    // a fresh Column/Loader reports 0 before its first implicitHeight; arm a pass later or first use plays a fake reveal
    gate: root._geometryReady
    Component.onCompleted: root._geometrySettle?.start()
    Component.onDestruction: root._geometrySettle?.stop()

    NumberAnimation {
        duration: root._enter ? (root.list ? Motion.listOpen : Motion.medium)
            : (root.list ? Motion.listClose : Motion.fast)
        easing.type: root._enter ? root.enterEasing : root.exitEasing
        easing.bezierCurve: root._enter ? root.enterCurve : root.exitCurve
    }
}
