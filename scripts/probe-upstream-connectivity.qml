import QtQuick
import Quickshell
import Quickshell.Bluetooth as Bt
import Quickshell.Networking as Net
import "services"

ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0

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
            const open = Network.wifiSecurityInfo(Net.WifiSecurityType.Open)
            const owe = Network.wifiSecurityInfo(Net.WifiSecurityType.Owe)
            const psk = Network.wifiSecurityInfo(Net.WifiSecurityType.WpaPsk)
            const sae = Network.wifiSecurityInfo(Net.WifiSecurityType.Sae)
            const enterprise = Network.wifiSecurityInfo(Net.WifiSecurityType.Wpa2Eap)
            const wep = Network.wifiSecurityInfo(Net.WifiSecurityType.StaticWep)
            const unknown = Network.wifiSecurityInfo(Net.WifiSecurityType.Unknown)
            root.check(open.passwordless && !open.secured && !open.psk,
                "open Wi-Fi does not request a password")
            root.check(owe.passwordless && !owe.secured && !owe.psk,
                "OWE Wi-Fi does not request a PSK")
            root.check(psk.psk && psk.secured && !psk.profileOnly
                && sae.psk && sae.secured && !sae.profileOnly,
                "WPA PSK and SAE remain PSK-capable")
            root.check(enterprise.profileOnly && wep.profileOnly && unknown.profileOnly,
                "enterprise WEP and unknown Wi-Fi require a stored profile")

            root.check(Bluetooth.isHardBlocked({ state: Bt.BluetoothAdapterState.Blocked })
                && !Bluetooth.isHardBlocked({ state: Bt.BluetoothAdapterState.Enabled }),
                "Bluetooth hard-block detection follows the adapter state enum")
            root.check(Bluetooth._attemptOutcome("pair", true, false, false, true, 0) === ""
                && Bluetooth._attemptOutcome("pair", true, false, false, false, 0) === "failed",
                "an active pairing survives the ordinary attempt timeout while an ended one fails")

            const pendingWas = Bluetooth._pendingAddr
            const kindWas = Bluetooth._pendingKind
            const errorWas = Bluetooth.errorAddr
            const errorKindWas = Bluetooth.errorKind
            Bluetooth._pendingAddr = "A"
            Bluetooth._pendingKind = "connect"
            Bluetooth.errorAddr = "B"
            Bluetooth.errorKind = "pair"
            Bluetooth._clearDeviceAttempt("A")
            root.check(Bluetooth._pendingAddr === "" && Bluetooth.errorAddr === "B",
                "clearing device A's attempt retains device B's error")
            Bluetooth.errorAddr = "A"
            Bluetooth._clearDeviceAttempt("A")
            root.check(Bluetooth.errorAddr === "", "clearing device A clears its own error")
            Bluetooth._pendingAddr = pendingWas
            Bluetooth._pendingKind = kindWas
            Bluetooth.errorAddr = errorWas
            Bluetooth.errorKind = errorKindWas

            console.log("PROBE-UPSTREAM-CONNECTIVITY " + (root.failures ? "failed " : "passed ")
                + root.checks + " checks")
            stop()
        }
    }
}
