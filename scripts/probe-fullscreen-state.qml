import QtQuick
import "services"

QtObject {
    id: root

    property int checks: 0
    property int failures: 0

    function check(condition: bool, message: string): void {
        checks++
        if (!condition) {
            failures++
            console.warn("PROBE-FAIL " + message)
        }
    }

    Component.onCompleted: {
        check(!FullscreenState.wanted && !FullscreenState.active && Compositor.refreshCount === 0,
            "no fullscreen demand stays dormant")

        ShellSettings.notifFullscreenSilence = true
        check(FullscreenState.wanted && Compositor.refreshCount === 1,
            "notification silence starts fullscreen tracking")
        Compositor.activeFullscreen = true
        check(FullscreenState.active, "notification silence observes the active fullscreen window")

        ShellSettings.notifFullscreenSilence = false
        check(!FullscreenState.wanted && !FullscreenState.active,
            "disabling notification silence stops fullscreen tracking")

        ShellSettings.osdEnabled = true
        check(!FullscreenState.wanted,
            "a floating OSD alone does not request fullscreen tracking")
        ShellSettings.osdBarIntegrated = true
        check(FullscreenState.wanted && FullscreenState.active && Compositor.refreshCount === 2,
            "an enabled integrated OSD starts tracking through the compositor facade")
        Compositor.activeFullscreen = false
        check(!FullscreenState.active, "fullscreen exit clears shared state")
        ShellSettings.osdEnabled = false
        check(!FullscreenState.wanted, "disabling the OSD removes its fullscreen demand")

        console.log("PROBE-FULLSCREEN-STATE " + (failures === 0 ? "passed " : "failed ")
            + checks + " checks")
    }
}
