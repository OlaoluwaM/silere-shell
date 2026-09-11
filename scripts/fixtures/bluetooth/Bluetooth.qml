pragma Singleton

import QtQuick
import Quickshell

// Only device events are simulated; the probe instantiates the real menu list.
Singleton {
    id: root

    readonly property bool available: true
    readonly property bool enabled: true
    readonly property bool managerAvailable: false
    readonly property string errorAddr: ""
    readonly property string errorKind: ""
    readonly property string lastError: ""
    property bool _devicesFrozen: false
    property bool scanRequested: false

    component Device: QtObject {
        property string address: ""
        property string deviceName: "Test headphones"
        property string icon: "audio-headset"
        property bool connected: true
        readonly property bool paired: true
        readonly property bool trusted: true
        readonly property bool pairing: false
        readonly property bool batteryAvailable: true
        readonly property int state: 0
    }

    readonly property Device first: Device { address: "first" }
    readonly property Device second: Device { address: "second" }
    readonly property var devices: [root.first, root.second]
    signal deviceRemoved(string address)

    function deviceLabel(device): string { return device.deviceName }
    function deviceGlyph(icon): string { return "" }
    function batteryPercent(device): int { return 40 }
    function setDevicesFrozen(frozen: bool): void { root._devicesFrozen = frozen }
    function setScan(on: bool): void { root.scanRequested = on }
    function abandonAttempt(): void {}
}
