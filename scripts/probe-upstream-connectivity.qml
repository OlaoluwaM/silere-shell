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

            console.log("PROBE-UPSTREAM-CONNECTIVITY " + (root.failures ? "failed " : "passed ")
                + root.checks + " checks")
            stop()
        }
    }
}
