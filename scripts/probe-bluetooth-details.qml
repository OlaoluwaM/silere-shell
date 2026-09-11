pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "services"
import "modules/menu"

ShellRoot {
    id: root

    property int step: 0
    property int checks: 0
    property int failures: 0

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    FloatingWindow {
        visible: true
        implicitWidth: 480
        implicitHeight: 420
        BluetoothList { id: list; width: 480; open: true }
    }

    Timer {
        interval: 250
        repeat: true
        running: true
        onTriggered: {
            switch (root.step++) {
            case 0:
                list._detailsAddr = "first"
                root.check(Bluetooth._devicesFrozen, "opening details freezes the published model")
                break
            case 1:
                Bluetooth.second.connected = false
                root.check(list._detailsAddr === "first" && Bluetooth._devicesFrozen,
                    "another device disconnecting preserves the selected details")
                break
            case 2:
                Bluetooth.first.connected = false
                root.check(list._detailsAddr === "" && !Bluetooth._devicesFrozen,
                    "the selected device disconnecting clears details and releases the model")
                break
            case 3:
                Bluetooth.first.connected = true
                root.check(list._detailsAddr === "", "reconnection does not reopen old details")
                break
            case 4:
                Bluetooth.second.connected = true
                list._detailsAddr = "second"
                Bluetooth.first.connected = false
                root.check(list._detailsAddr === "second" && Bluetooth._devicesFrozen,
                    "switching selection isolates later events from the previous device")
                break
            case 5:
                Bluetooth.second.connected = false
                root.check(list._detailsAddr === "" && !Bluetooth._devicesFrozen,
                    "the second device's disconnect also clears selection")
                break
            case 6:
                Bluetooth.first.connected = true
                list._detailsAddr = "first"
                list.open = false
                root.check(list._detailsAddr === "" && !Bluetooth._devicesFrozen
                        && !Bluetooth.scanRequested, "closing the list releases details and discovery")
                break
            default:
                console.log("PROBE-BLUETOOTH-DETAILS " + (root.failures ? "failed " : "passed ")
                    + root.checks + " checks")
                stop()
            }
        }
    }
}
