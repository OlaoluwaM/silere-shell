pragma ComponentBehavior: Bound

import QtQuick
import "../../services"
import "controls"

// the connected Wi-Fi entry's disclosure content: read-only radio/IP facts,
// a band picker for the profile, and a delegated "edit connection" launch
Column {
    id: root

    property bool open: false

    width: parent ? parent.width : 0
    spacing: 0
    bottomPadding: 4

    onOpenChanged: WifiProfile.setActive(root.open)
    Component.onCompleted: WifiProfile.setActive(root.open)
    Component.onDestruction: WifiProfile.setActive(false)

    DetailRow { label: "SSID";         value: Network.connectionName }
    DetailRow { label: "Frequency";    value: WifiProfile.bandFrequencyLabel.length > 0 ? WifiProfile.bandFrequencyLabel : "—" }
    DetailRow { label: "Signal";       value: Network.signalStrength + "%" }
    DetailRow { label: "Security";     value: WifiProfile.securityLabel.length > 0 ? WifiProfile.securityLabel : "—" }
    DetailRow { label: "IPv4 Address"; value: WifiProfile.ipv4Address.length > 0 ? WifiProfile.ipv4Address : "—" }
    DetailRow { label: "Gateway";      value: WifiProfile.gateway.length > 0 ? WifiProfile.gateway : "—" }
    DetailRow { label: "DNS";          value: WifiProfile.dnsLabel.length > 0 ? WifiProfile.dnsLabel : "—" }

    Item { width: 1; height: 6 }

    ChoiceChipRow {
        width: root.width
        label: "Band"
        enabled: WifiProfile.toolAvailable && WifiProfile.profileUuid.length > 0
        currentValue: WifiProfile.bandSetting
        model: [
            { value: "",   label: "Auto" },
            { value: "bg", label: "2.4 GHz" },
            { value: "a",  label: "5 GHz" }
        ]
        onChosen: (v) => WifiProfile.setBand(v)
    }

    InlineOptionRow {
        width: root.width
        visible: WifiProfile.editorAvailable
        glyph: "󰒓"
        label: "Edit connection…"
        onTriggered: WifiProfile.launchEditor()
    }

    HintText {
        visible: WifiProfile.lastError.length > 0
        text: WifiProfile.lastError
    }
}
