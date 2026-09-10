pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "config"
import "services"

ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0
    property bool reduceMotionWas: false
    property var nextStep: null

    QtObject {
        id: bumpTarget
        property real value: 1.0
    }

    BumpAnimation {
        id: bump
        target: bumpTarget
        targetProperty: "value"
        peak: 1.2
    }

    Timer {
        id: wait
        onTriggered: {
            const step = root.nextStep
            root.nextStep = null
            if (step) step()
        }
    }

    Connections {
        target: ShellSettings
        function onReadyChanged(): void {
            if (ShellSettings.ready) Qt.callLater(root.run)
        }
    }

    function check(condition: bool, label: string): void {
        root.checks++
        if (condition) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    function after(delay: int, step): void {
        root.nextStep = step
        wait.interval = delay
        wait.restart()
    }

    function run(): void {
        root.reduceMotionWas = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = false
        root.check(Motion.bumpRise === 70 && Motion.bumpSettle === 140,
            "normal motion exposes the shared 70ms rise and 140ms settle")
        bump.restart()
        root.check(bump.running,
            "the real bump helper starts against its configured target property")
        root.after(40, root.retriggerDuringRise)
    }

    function retriggerDuringRise(): void {
        root.check(bumpTarget.value > 1 && bumpTarget.value <= bump.peak,
            "the helper raises its target before settling")
        const valueBeforeRestart = bumpTarget.value
        bump.restart()
        root.check(bump.running
                && Math.abs(bumpTarget.value - valueBeforeRestart) < 0.001,
            "restarting during the rise preserves the in-flight value")
        root.after(90, root.retriggerDuringSettle)
    }

    function retriggerDuringSettle(): void {
        root.check(bump.running && bumpTarget.value > bump.rest
                && bumpTarget.value < bump.peak,
            "the helper is settling before a second restart")
        const valueBeforeRestart = bumpTarget.value
        bump.restart()
        root.check(bump.running
                && Math.abs(bumpTarget.value - valueBeforeRestart) < 0.001,
            "restarting during the settle preserves the in-flight value")
        root.after(40, root.retireRunning)
    }

    function retireRunning(): void {
        root.check(bump.running && bumpTarget.value > bump.rest,
            "the retriggered bump remains in flight before retirement")
        bump.retire()
        root.check(!bump.running && bumpTarget.value === bump.rest,
            "retiring a running bump restores its target to rest")
        bump.restart()
        root.after(240, root.completed)
    }

    function completed(): void {
        root.check(!bump.running && bumpTarget.value === bump.rest,
            "a completed bump settles its target at rest")
        bumpTarget.value = 0.4
        bump.retire()
        root.check(!bump.running && bumpTarget.value === bump.rest,
            "retiring an already-stopped bump restores its target to rest")
        bumpTarget.value = 0.6
        bump.retire()
        root.check(!bump.running && bumpTarget.value === bump.rest,
            "repeated retire calls remain idempotent and restore rest")

        ShellSettings.reduceMotion = false
        bump.restart()
        root.after(40, root.reduceMotionDuringRun)
    }

    function reduceMotionDuringRun(): void {
        root.check(bump.running && bumpTarget.value > bump.rest,
            "a bump is still in flight before reduce motion changes")
        ShellSettings.reduceMotion = true
        root.check(Motion.bumpRise === 0 && Motion.bumpSettle === 0,
            "reduce motion collapses both shared bump durations")
        root.after(40, root.reducedMotionSettled)
    }

    function reducedMotionSettled(): void {
        root.check(!bump.running && bumpTarget.value === bump.rest,
            "enabling reduce motion during a bump settles it at rest")
        bumpTarget.value = 0.4
        bump.restart()
        root.after(20, root.reducedMotionCompleted)
    }

    function reducedMotionCompleted(): void {
        root.check(!bump.running && bumpTarget.value === bump.rest,
            "a reduced-motion bump completes immediately at rest")
        ShellSettings.reduceMotion = root.reduceMotionWas
        console.warn("PROBE-BUMP "
            + (root.failures === 0 ? "passed " : "failed ")
            + root.checks + " checks")
    }

    Component.onCompleted: {
        if (ShellSettings.ready) Qt.callLater(root.run)
    }
}
