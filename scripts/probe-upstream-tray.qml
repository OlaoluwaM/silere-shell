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

    QtObject {
        id: rootFlyout
        property bool opened: true
        property bool hovered: false
        property var parentFlyout: null
    }
    QtObject {
        id: childFlyout
        property bool opened: true
        property bool hovered: false
        property var parentFlyout: rootFlyout
    }
    QtObject {
        id: grandchildFlyout
        property bool opened: true
        property bool hovered: false
        property var parentFlyout: childFlyout
    }

    Timer {
        interval: 0
        running: true
        onTriggered: {
            grandchildFlyout.hovered = true
            root.check(TrayMenuState.branchHovered(rootFlyout, [grandchildFlyout]),
                "a hovered grandchild retains every open ancestor")
            root.check(TrayMenuState.branchHovered(childFlyout, [grandchildFlyout]),
                "a hovered grandchild retains its direct parent")

            grandchildFlyout.hovered = false
            childFlyout.hovered = true
            root.check(TrayMenuState.branchHovered(rootFlyout, [childFlyout]),
                "a hovered child retains its parent")

            childFlyout.opened = false
            root.check(!TrayMenuState.branchHovered(rootFlyout, [childFlyout]),
                "a closed child does not retain a parent flyout")

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
            button._armedAtMs = Date.now() - 3001
            button.request()
            root.check(button.armed && root.confirmed === 0
                    && Date.now() - button._armedAtMs < Metrics.confirmGuardMs,
                "an expired confirmation rearms when its cleanup timer has not fired yet")
            button._armedAtMs = Date.now() + 1000
            button.request()
            root.check(button.armed && root.confirmed === 0
                    && button._armedAtMs <= Date.now(),
                "a backwards clock change restarts the confirmation window")
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
