pragma ComponentBehavior: Bound

import QtQuick
import "../../services"
import "controls"

// a connected device's disclosure content: read-only identity/battery/pairing
// facts read straight off the live BluetoothDevice, plus a delegated "open
// bluetooth manager" launch — mirrors WifiDetails' treatment
Column {
    id: root

    required property var device

    width: parent ? parent.width : 0
    spacing: 0
    bottomPadding: 4

    DetailRow { label: "Name";       value: Bluetooth.deviceLabel(root.device) }
    DetailRow {
        label: "Address"
        value: root.device && root.device.address.length > 0 ? root.device.address : "—"
    }
    DetailRow {
        visible: root.device && root.device.batteryAvailable
        label: "Battery"
        value: {
            const b = Bluetooth.batteryPercent(root.device)
            return b >= 0 ? b + "%" : "—"
        }
    }
    DetailRow { label: "Connection"; value: root.device && root.device.connected ? "Connected" : "Not connected" }
    DetailRow { label: "Paired";     value: root.device && root.device.paired ? "Yes" : "No" }
    DetailRow { label: "Trusted";    value: root.device && root.device.trusted ? "Yes" : "No" }

    InlineOptionRow {
        width: root.width
        visible: Bluetooth.managerAvailable
        glyph: "󰒓"
        label: "Open bluetooth manager…"
        onTriggered: Bluetooth.launchManager()
    }

    HintText {
        visible: Bluetooth.lastError.length > 0
        text: Bluetooth.lastError
    }
}
