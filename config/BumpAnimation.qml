import QtQuick

// rise off rest, settle back onto it: the shell's one tactile acknowledgement. A restart
// carries its in-flight value into the new rise; lifecycle cleanup calls retire explicitly
SequentialAnimation {
    id: bump

    property var    target
    property string targetProperty
    property real   peak: Motion.hoverScale
    property real   rest: 1.0
    property int    riseEasing:   Easing.OutQuad
    property int    settleEasing: Easing.OutCubic
    readonly property bool _motionSuppressed: Motion.bumpRise === 0
        && Motion.bumpSettle === 0

    on_MotionSuppressedChanged: if (_motionSuppressed) retire()

    // callers can retire an already-stopped cell after parking it out of band, so cleanup
    // must write rest itself. The plain write is safe where MotionBehavior's was not: a
    // bump target is animation-owned, never a binding
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
