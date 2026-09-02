import QtQuick

MotionBehavior {
    ColorAnimation {
        duration: Motion.palette
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.standardDecel
    }
}
