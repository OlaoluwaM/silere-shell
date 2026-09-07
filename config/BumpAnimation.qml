import QtQuick

// rise off rest, settle back onto it: the shell's one tactile acknowledgement. stopping
// mid-flight lands on rest, so a gate closing cannot strand the value part-way up
SequentialAnimation {
    id: bump

    property var    target
    property string targetProperty
    property real   peak: Motion.hoverScale
    property real   rest: 1.0
    property int    riseEasing:   Easing.OutQuad
    property int    settleEasing: Easing.OutCubic

    onRunningChanged: if (!running && target && targetProperty) target[targetProperty] = rest

    // callers park a cell out of band before sleeping it, so this cannot lean on the stop
    // handler above. The plain write is safe where MotionBehavior's was not: a bump target
    // is animation-owned, never a binding
    function retire(): void {
        stop()
        if (target && targetProperty) target[targetProperty] = rest
    }

    NumberAnimation {
        target: bump.target; property: bump.targetProperty
        to: bump.peak; duration: Motion.bumpRise; easing.type: bump.riseEasing
    }
    NumberAnimation {
        target: bump.target; property: bump.targetProperty
        to: bump.rest; duration: Motion.bumpSettle; easing.type: bump.settleEasing
    }
}
