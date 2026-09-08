pragma ComponentBehavior: Bound

import QtQuick
import "../../../../config"
import "../../../../services"

Item {
    id: root

    required property bool barActive
    property real pulseOpacity: 1.0
    property real shakeX: 0
    property bool settled: false
    readonly property bool motionActive: !root.settled && root.barActive
        && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)

    SequentialAnimation {
        running: root.motionActive
        loops: Animation.Infinite
        onRunningChanged: if (!running) {
            root.pulseOpacity = 1.0
            root.shakeX = 0
        }
        NumberAnimation { target: root; property: "shakeX"; to: 2.5; duration: Motion.ms(55); easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -2.5; duration: Motion.ms(55); easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 2.5; duration: Motion.ms(55); easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: Motion.ms(55); easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "pulseOpacity"; to: 0.3; duration: Motion.ms(550); easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "pulseOpacity"; to: 1.0; duration: Motion.ms(550); easing.type: Easing.InOutSine }
    }

    Timer {
        interval: 15000
        running: root.motionActive
        onTriggered: root.settled = true
    }
}
