import QtQuick
import Quickshell
import "services"

ShellRoot {
    id: root

    property int step: 0
    property int failures: 0

    function check(ok: bool, label: string): void {
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    Component.onCompleted: console.log("power backend", PowerProfiles.backend)

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            switch (root.step++) {
            case 0:
                root.check(SystemTools.ready && PowerProfiles.available,
                    "the profile tool is detected before the panel opens")
                root.check(PowerProfiles.profiles.length === 0,
                    "an initial list without profiles leaves the picker empty")
                ControlSurfaces.opened()
                break
            case 1:
                root.check(PowerProfiles.profile === "balanced",
                    "opening the panel reads the current profile")
                root.check(JSON.stringify(PowerProfiles.profiles)
                        === '["power-saver","balanced","performance"]',
                    "opening the panel recovers the missing profile choices")
                ControlSurfaces.opened()
                break
            default:
                console.log("PROBE-POWER-RECOVERY " + (root.failures ? "failed" : "passed"))
                stop()
            }
        }
    }
}
