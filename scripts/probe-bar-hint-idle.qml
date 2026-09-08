pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "config"
import "services"
import "modules/bar" as Bar

ShellRoot {
    id: root

    property int phase: 0
    property int checks: 0
    property int failures: 0
    readonly property var probeScreen: Quickshell.screens.length > 0
        ? Quickshell.screens[0] : null

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    function resetState(): void {
        hintLoader.active = false
        BarHintState.open = false
        BarHintState.triggerScreen = null
        BarHintState.anchorX = 0
        BarHintState.text = ""
        Idle.isIdle = false
        ShellSettings.reduceMotion = false
    }

    function loadPhase(next: int): void {
        root.resetState()
        root.phase = next
        Qt.callLater(root.startPhase)
    }

    function startPhase(): void {
        if (!root.probeScreen) {
            root.check(false, "the Wayland runtime provides a probe screen")
            root.finish()
            return
        }

        BarHintState.triggerScreen = root.probeScreen
        BarHintState.anchorX = 80
        BarHintState.text = "Idle motion probe"

        if (root.phase === 0) {
            Idle.isIdle = true
            hintLoader.active = true
        } else if (root.phase === 1) {
            BarHintState.open = true
            hintLoader.active = true
        } else if (root.phase === 2) {
            BarHintState.open = true
            hintLoader.active = true
        } else if (root.phase === 3) {
            ShellSettings.reduceMotion = true
            BarHintState.open = true
            hintLoader.active = true
        } else {
            root.finish()
        }
    }

    function inspectLoaded(item): void {
        if (!item) {
            root.check(false, "bar hint popup loads")
            root.finish()
            return
        }

        if (root.phase === 0) {
            root.check(item._ready && item._op === 0
                    && item._rise === item._hiddenRise(),
                "a hint born while idle settles hidden without scheduling a frame")
        } else if (root.phase === 1) {
            root.check(!item._ready,
                "the active hint starts with an entrance frame pending")
            Idle.isIdle = true
            root.check(item._ready && item._op === 0
                    && item._rise === item._hiddenRise(),
                "idle during the pending entrance settles the now-closed hint")
        } else if (root.phase === 2) {
            item._ready = true
            item._op = 1
            item._rise = 0
            BarHintState.open = false
            root.check(item._op > 0,
                "closing a visible hint starts its exit")
            Idle.isIdle = true
            root.check(item._op === 0 && item._rise === item._hiddenRise(),
                "idle interrupts an active exit at its hidden endpoint")
        } else if (root.phase === 3) {
            root.check(item._ready && item._op === 1 && item._rise === 0,
                "reduce motion still opens at the visible endpoint")
            BarHintState.open = false
            root.check(item._op === 0 && item._rise === item._hiddenRise(),
                "reduce motion still closes at the hidden endpoint")
        }

        root.loadPhase(root.phase + 1)
    }

    function finish(): void {
        root.resetState()
        if (root.failures === 0)
            console.warn("PROBE-BAR-HINT-IDLE passed " + root.checks + " checks")
        else
            console.warn("PROBE-BAR-HINT-IDLE failed " + root.failures
                + "/" + root.checks + " checks")
    }

    Loader {
        id: hintLoader
        active: false
        sourceComponent: Component {
            Bar.BarHintPopup {
                targetScreen: root.probeScreen
            }
        }
        onLoaded: root.inspectLoaded(item)
    }

    Component.onCompleted: root.loadPhase(0)
}
