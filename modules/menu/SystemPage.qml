pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"

PageShell {
    id: root

    implicitHeight: _col.implicitHeight

    // the fetch card's uptime line only needs to stay fresh while this page is
    // actually the one loaded; MenuWindow's systemLoader (released a beat after
    // the tab is left, same as the settings/recent loaders) creates and destroys
    // this page, same push-in split WifiDetails uses for WifiProfile's own
    // disclosure-gated polling and this content used while it still lived
    // inside Settings > System
    Component.onCompleted: SysFetch.setActive(true)
    Component.onDestruction: SysFetch.setActive(false)

    function _titleCase(s: string): string {
        return String(s || "").split(/[\s_-]+/).filter(w => w.length > 0)
            .map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ")
    }
    function _profileHint(value: string): string {
        switch (String(value || "").toLowerCase()) {
        case "quiet":
        case "power-saver": return "Lower clocks, quieter fans"
        case "balanced":    return "Everyday default"
        case "performance": return "Highest clocks, louder fans"
        default:            return ""
        }
    }
    readonly property var _profileModel: PowerProfiles.choices.map(p =>
        ({ value: p, label: root._titleCase(p), description: root._profileHint(p) }))

    Column {
        id: _col
        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            height: Metrics.rowHeightFor(38)

            ShellText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "System"
                color: Theme.text
                font.pixelSize: Settings.fontSize + 4
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        SectionLabel { label: "POWER PROFILE"; first: true; visible: PowerProfiles.available }
        SettingsCard {
            visible: PowerProfiles.available
            // the card's radius and divider scans walk its column, and a Repeater
            // parents its delegates there, so these rows join them like literal ones
            Repeater {
                model: root._profileModel
                delegate: ChoiceListRow {
                    required property var modelData
                    groupName: "Power profile"
                    value: modelData.value
                    label: modelData.label
                    description: modelData.description
                    // a pick before the daemon answers would be refused or overwritten, and
                    // until then no row can claim to be current
                    enabled: PowerProfiles.confirmed
                    active: PowerProfiles.confirmed && modelData.value === PowerProfiles.current
                    onChosen: (v) => PowerProfiles.setProfile(v)
                }
            }
            // stays while the daemon is silent, so the inert rows are never left unexplained
            CollapsibleSection {
                expanded: !PowerProfiles.confirmed
                Item {
                    width: parent.width
                    height: Metrics.rowHeightFor(36)
                    ShellText {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Waiting for the power daemon…"
                        elide: Text.ElideRight
                        color: Theme.withAlpha(Theme.subtext, 0.5)
                        font.pixelSize: Settings.fontLabel
                    }
                }
            }
        }

        SectionLabel { label: "SYSTEM"; first: !PowerProfiles.available }
        SettingsCard {
            DetailRow { label: "OS";         value: SysFetch.osName.length > 0 ? SysFetch.osName : "—" }
            DetailRow { label: "Kernel";     value: SysFetch.kernel.length > 0 ? SysFetch.kernel : "—" }
            DetailRow { label: "Hostname";   value: SysFetch.hostname.length > 0 ? SysFetch.hostname : "—" }
            DetailRow { label: "Uptime";     value: SysFetch.uptimeLabel }
            DetailRow { label: "Compositor"; value: SysFetch.compositorLabel }
            DetailRow { label: "Shell";      value: SysFetch.shellLabel }

            Item {
                width: 1; height: 6
                // opts this padding-only spacer out of RowDividers' "present row" count
                // (same contract HintText/SectionLabel declare) so it doesn't draw a
                // faint divider line of its own or steal the card's bottom-radius edge
                // from the last real DetailRow
                readonly property bool suppressDividerAbove: true
            }
        }
    }
}
