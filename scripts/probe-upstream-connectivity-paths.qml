import QtQuick
import Quickshell
import Quickshell.Bluetooth as Bt
import Quickshell.Networking as Net
import "services"
import "modules/menu"
import "modules/menu/controls"

ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0
    property int rowPhase: 0
    property int pairGuardPhase: 0
    property double pairGuardStartedAtMs: 0
    property Item wifiRow: null
    property QtObject wifiConfirm: null
    property Item bluetoothRow: null
    property QtObject bluetoothConfirm: null

    readonly property var wifiSavedRow: ({
        ssid: "saved", label: "saved", glyph: "wifi", secured: true,
        psk: true, profileOnly: false,
        active: false, known: true
    })
    readonly property var wifiOtherRow: ({
        ssid: "other", label: "other", glyph: "wifi", secured: true,
        psk: true, profileOnly: false,
        active: false, known: true
    })

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    function finishPairGuardProbe(): void {
        console.log("PROBE-UPSTREAM-CONNECTIVITY-PATHS "
            + (root.failures ? "failed " : "passed ") + root.checks + " checks")
        pairGuardElapsed.stop()
    }

    function findObject(object, predicate, seen): var {
        if (!object || seen.indexOf(object) >= 0) return null
        seen.push(object)
        if (predicate(object)) return object
        const groups = [object.data || [], object.children || []]
        for (let g = 0; g < groups.length; g++) {
            const group = groups[g]
            for (let i = 0; i < group.length; i++) {
                const found = root.findObject(group[i], predicate, seen)
                if (found) return found
            }
        }
        return null
    }

    function rowFor(list, role: string, value: string): var {
        return root.findObject(list, object => typeof object._middleTap === "function"
            && object.parent?.modelData?.[role] === value, [])
    }

    function confirmFor(list): var {
        return root.findObject(list, object => typeof object.tryConfirm === "function"
            && object.key !== undefined, [])
    }

    function rebindOnDisarm(confirm, row, replacement): void {
        const hook = function() {
            if (confirm.key !== "") return
            confirm.keyChanged.disconnect(hook)
            row.parent.modelData = replacement
        }
        confirm.keyChanged.connect(hook)
    }

    QtObject {
        id: enterprise
        property string name: "enterprise"
        property real signalStrength: 1
        property int security: Net.WifiSecurityType.Wpa2Eap
        property bool known: true
        property bool connected: false
        property bool connectCalled: false
        property bool pskCalled: false
        property bool forgot: false
        function connect(): void { connectCalled = true }
        function connectWithPsk(password: string): void { pskCalled = true }
        function forget(): void { forgot = true }
    }
    QtObject {
        id: psk
        property string name: "psk"
        property real signalStrength: 0.8
        property int security: Net.WifiSecurityType.Sae
        property bool known: false
        property bool connected: false
        property bool connectCalled: false
        property bool pskCalled: false
        function connect(): void { connectCalled = true }
        function connectWithPsk(password: string): void { pskCalled = password === "secret" }
        function forget(): void {}
    }
    QtObject {
        id: saved
        property string name: "saved"
        property real signalStrength: 0.7
        property int security: Net.WifiSecurityType.Wpa2Psk
        property bool known: true
        property bool connected: true
        property bool forgot: false
        property bool connectCalled: false
        function connect(): void { connectCalled = true }
        function connectWithPsk(password: string): void {}
        function forget(): void { forgot = true }
    }
    QtObject {
        id: otherWifi
        property string name: "other"
        property real signalStrength: 0.6
        property int security: Net.WifiSecurityType.Wpa2Psk
        property bool known: true
        property bool connected: false
        property bool connectCalled: false
        property bool forgot: false
        function connect(): void { connectCalled = true }
        function connectWithPsk(password: string): void {}
        function forget(): void { forgot = true }
    }
    QtObject {
        id: wifiDevice
        property int type: Net.DeviceType.Wifi
        property var networks: ({ values: [enterprise, psk, saved, otherWifi] })
        property bool connected: false
        property bool scannerEnabled: false
        function disconnect(): void {}
    }

    QtObject {
        id: pairA
        property string name: "pair A"
        property string address: "A"
        property bool paired: false
        property bool connected: false
        property bool pairing: false
        property bool batteryAvailable: false
        property bool trusted: false
        property int state: Bt.BluetoothDeviceState.Disconnected
        property bool forgot: false
        property bool connectCalled: false
        function connect(): void { connectCalled = true }
        function disconnect(): void {}
        function pair(): void { pairing = true }
        function cancelPair(): void { pairing = false }
        function forget(): void { forgot = true }
    }
    QtObject {
        id: pendingB
        property string name: "pending B"
        property string address: "B"
        property bool paired: true
        property bool connected: false
        property bool pairing: false
        property bool batteryAvailable: false
        property bool trusted: false
        property int state: Bt.BluetoothDeviceState.Connecting
        property bool forgot: false
        property bool connectCalled: false
        function connect(): void { connectCalled = true }
        function disconnect(): void {}
        function pair(): void {}
        function cancelPair(): void {}
        function forget(): void { forgot = true }
    }
    QtObject {
        id: adapter
        property bool enabled: true
        property int state: Bt.BluetoothAdapterState.Enabled
        property bool pairable: true
        property int pairableTimeout: 0
        property bool discovering: false
        property QtObject devices: btDevices
    }
    QtObject {
        id: btDevices
        property var values: [pairA, pendingB]
    }

    ArmConfirm { id: confirm }

    Window {
        visible: true
        width: 640
        height: 480

        WifiList {
            id: actualWifiList
            width: 300
            height: 300
        }
        BluetoothList {
            id: actualBluetoothList
            x: 320
            width: 300
            height: 300
        }
    }

    Timer {
        interval: 0
        running: true
        onTriggered: {
            Network._devices = [wifiDevice]
            Network.connectWifi("enterprise", "secret")
            root.check(enterprise.connectCalled && !enterprise.pskCalled,
                "enterprise credentials cannot reach connectWithPsk")
            Network.connectWifi("psk", "secret")
            root.check(psk.pskCalled && !psk.connectCalled,
                "PSK credentials reach connectWithPsk")

            Network.wifiError = "saved"
            saved.connected = true
            Network.forgetWifi("saved")
            root.check(!saved.forgot && Network.wifiError === "saved",
                "an active saved profile cannot be forgotten")
            saved.connected = false
            Network.forgetWifi("saved")
            root.check(saved.forgot && Network.wifiError === "",
                "forgetting a disconnected saved profile clears its stale error")

            root.check(!confirm.tryConfirm("forget:saved"),
                "the first middle-click confirmation arms")
            confirm.armedAtMs = Date.now() - 401
            root.check(confirm.tryConfirm("forget:saved"),
                "the guarded second middle-click confirmation succeeds")

            Bluetooth.adapter = adapter
            pairA.paired = true
            Network.wifiNetworks = [root.wifiSavedRow, root.wifiOtherRow]
            Bluetooth.devices = [pairA, pendingB]
            actualWifiList.open = true
            actualBluetoothList.open = true
            rowProbe.start()
        }
    }

    Timer {
        id: rowProbe
        interval: 20
        repeat: true
        onTriggered: {
            if (root.rowPhase === 0) {
                root.wifiRow = root.rowFor(actualWifiList, "ssid", "saved")
                root.wifiConfirm = root.confirmFor(actualWifiList)
                root.bluetoothRow = root.rowFor(actualBluetoothList, "address", "A")
                root.bluetoothConfirm = root.confirmFor(actualBluetoothList)
                if (!root.wifiRow || !root.wifiConfirm
                        || !root.bluetoothRow || !root.bluetoothConfirm) return
                root.rowPhase++
                return
            }

            if (root.rowPhase === 1) {
                saved.forgot = false
                otherWifi.forgot = false
                root.wifiRow._middleTap()
                root.wifiConfirm.armedAtMs = Date.now() - 401
                root.rebindOnDisarm(root.wifiConfirm, root.wifiRow, root.wifiOtherRow)
                root.wifiRow._middleTap()
                root.check(root.wifiRow.parent.modelData.ssid === "other"
                        && saved.forgot && !otherWifi.forgot,
                    "Wi-Fi row forget dispatches the identity captured before a synchronous rebind")
                root.rowPhase++
                return
            }

            if (root.rowPhase === 2) {
                root.wifiRow.parent.modelData = root.wifiSavedRow
                saved.connectCalled = false
                otherWifi.connectCalled = false
                root.wifiRow._middleTap()
                root.rebindOnDisarm(root.wifiConfirm, root.wifiRow, root.wifiOtherRow)
                root.wifiRow._activate()
                root.check(root.wifiRow.parent.modelData.ssid === "other"
                        && saved.connectCalled && !otherWifi.connectCalled,
                    "Wi-Fi row activation uses the identity and state captured before disarming")
                root.rowPhase++
                return
            }

            if (root.rowPhase === 3) {
                pairA.forgot = false
                pendingB.forgot = false
                root.bluetoothRow._middleTap()
                root.bluetoothConfirm.armedAtMs = Date.now() - 401
                root.rebindOnDisarm(root.bluetoothConfirm, root.bluetoothRow, pendingB)
                root.bluetoothRow._middleTap()
                root.check(root.bluetoothRow.parent.modelData.address === "B"
                        && pairA.forgot && !pendingB.forgot,
                    "Bluetooth row forget dispatches the identity captured before a synchronous rebind")
                root.rowPhase++
                return
            }

            if (root.rowPhase === 4) {
                root.bluetoothRow.parent.modelData = pairA
                pairA.connectCalled = false
                pendingB.connectCalled = false
                root.bluetoothRow._middleTap()
                root.rebindOnDisarm(root.bluetoothConfirm, root.bluetoothRow, pendingB)
                root.bluetoothRow._activate()
                root.check(root.bluetoothRow.parent.modelData.address === "B"
                        && pairA.connectCalled && !pendingB.connectCalled,
                    "Bluetooth row activation uses the identity and state captured before disarming")
                actualWifiList.open = false
                actualBluetoothList.open = false
                rowProbe.stop()

                pairA.paired = false
                pairA.connectCalled = false
                pairA.pairing = false
                adapter.pairable = false
                adapter.pairableTimeout = 17
                Bluetooth.pairDevice("A")
                root.check(Bluetooth._pendingAddr === "A" && pairA.pairing,
                    "pairing starts an attempt for its addressed device")
                root.check(adapter.pairable && adapter.pairableTimeout === 60,
                    "a pairing attempt owns and bounds adapter pairability when it enables it")
                root.pairGuardStartedAtMs = Date.now()
                pairGuardElapsed.restart()
            }
        }
    }

    Timer {
        id: pairGuardElapsed
        interval: 10
        repeat: true
        onTriggered: {
            if (Date.now() - root.pairGuardStartedAtMs > 2000) {
                root.check(false, "the pairing guard completes before its fixture watchdog")
                root.finishPairGuardProbe()
                return
            }

            if (root.pairGuardPhase === 0 && Bluetooth._guardExtensions >= 1) {
                root.check(Bluetooth._pendingAddr === "A" && Bluetooth.errorAddr === "",
                    "an active pairing survives its first guard interval")
                root.pairGuardPhase++
            }

            if (root.pairGuardPhase === 1 && Bluetooth._pendingAddr === "") {
                root.check(Bluetooth.errorAddr === "A" && Bluetooth.errorKind === "pair"
                        && Bluetooth._guardExtensions === 8,
                    "a pairing that never clears fails on the ninth guard interval")
                root.check(!adapter.pairable && adapter.pairableTimeout === 17,
                    "a timed-out pairing restores pairability owned by this service")
                pairA.paired = false
                pairA.pairing = false
                adapter.pairable = true
                adapter.pairableTimeout = 31
                Bluetooth.pairDevice("A")
                root.check(Bluetooth._pendingAddr === "A" && adapter.pairableTimeout === 31,
                    "an externally pairable adapter remains owned by its original actor")
                root.pairGuardPhase++
                root.pairGuardStartedAtMs = Date.now()
                restart()
                return
            }

            if (root.pairGuardPhase === 2 && Bluetooth._guardExtensions >= 1) {
                pairA.paired = true
                pairA.pairing = false
                root.pairGuardPhase++
            }

            if (root.pairGuardPhase === 3 && Bluetooth._pendingAddr === "") {
                root.check(Bluetooth._pendingAddr === "" && Bluetooth.errorAddr === ""
                        && adapter.pairable && adapter.pairableTimeout === 31,
                    "a successful pairing before the cap leaves externally owned pairability intact")
                pairA.paired = false
                pairA.pairing = false
                adapter.pairable = false
                adapter.pairableTimeout = 7
                Bluetooth.pairDevice("A")
                root.pairGuardPhase++
                root.pairGuardStartedAtMs = Date.now()
                restart()
                return
            }

            if (root.pairGuardPhase === 4 && Bluetooth._guardExtensions >= 1) {
                root.check(Bluetooth._pendingAddr === "A" && Bluetooth.errorAddr === ""
                        && Bluetooth._guardExtensions === 1,
                    "a fresh pairing attempt receives a fresh guard budget")
                root.pairGuardPhase++
            }

            if (root.pairGuardPhase === 5 && Bluetooth._pendingAddr === "") {
                root.check(Bluetooth.errorAddr === "A" && Bluetooth.errorKind === "pair"
                        && Bluetooth._guardExtensions === 8,
                    "the fresh pairing attempt also fails on its ninth guard interval")
                root.check(!adapter.pairable && adapter.pairableTimeout === 7,
                    "the fresh timed-out attempt restores its own adapter state")
                Bluetooth._pendingAddr = "B"
                Bluetooth._pendingKind = "connect"
                Bluetooth.errorAddr = "B"
                Bluetooth.errorKind = "pair"
                Bluetooth.disconnectDevice("A")
                root.check(Bluetooth._pendingAddr === "B" && Bluetooth.errorAddr === "B",
                    "disconnecting A leaves B's attempt and error intact")
                pairA.paired = true
                pairA.connected = false
                Bluetooth.forgetDevice("A")
                root.check(pairA.forgot && Bluetooth._pendingAddr === "B",
                    "forgetting A leaves B's pending attempt intact")
                root.finishPairGuardProbe()
            }
        }
    }
}
