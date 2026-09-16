import QtQuick
import Quickshell
import "config"
import "services"
import "modules/common"

ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0
    property int confirmed: 0

    Component {
        id: confirmButtonFactory
        ConfirmButton {
            label: "Remove"
            onConfirmed: root.confirmed++
        }
    }

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    Timer {
        interval: 0
        running: true
        onTriggered: {
            const button = confirmButtonFactory.createObject(root)
            button.request()
            button.enabled = false
            root.check(!button.armed, "disabling disarms a pending confirmation")
            button.enabled = true
            button.request()
            button.busy = true
            root.check(!button.armed, "becoming busy disarms a pending confirmation")
            button.busy = false
            button.request()
            button.visible = false
            root.check(!button.armed, "hiding disarms a pending confirmation")
            button.visible = true
            button.request()
            button._armedAtMs = Date.now() - Metrics.confirmGuardMs - 1
            button.request()
            root.check(root.confirmed === 1,
                "a re-enabled accessibility request confirms only after a guarded second action")
            button.destroy()

            console.log("PROBE-UPSTREAM-TRAY " + (root.failures ? "failed " : "passed ")
                + root.checks + " checks")
            stop()
        }
    }
}
