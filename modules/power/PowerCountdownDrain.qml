import QtQuick
import "../../services"

// The countdown bar's fill, shared by the desktop's countdown card and the lock's. It drains
// toward the wall-clock deadline, so a card built part-way through a countdown starts where
// the countdown is, not from full; with reduced motion it steps with the seconds instead.
QtObject {
    id: root

    property int seconds: 60
    property real deadline: 0
    property int remaining: 0
    property real progress: 1.0

    // the duration is the countdown itself, which Motion must not scale or the bar would lie
    readonly property NumberAnimation _drain: NumberAnimation {
        target: root
        property: "progress"
        to: 0.0
        easing.type: Easing.Linear
    }

    function start(): void {
        root._drain.stop()
        const total = root.seconds * 1000
        const left = Math.max(0, Math.min(total, root.deadline - Date.now()))
        root.progress = left / total
        if (ShellSettings.reduceMotion || left <= 0) return
        root._drain.from = root.progress
        root._drain.duration = left
        root._drain.start()
    }

    // the bar holds where it stopped
    function stop(): void {
        root._drain.stop()
    }

    onRemainingChanged: {
        if (ShellSettings.reduceMotion) root.progress = root.remaining / root.seconds
    }
}
