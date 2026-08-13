pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../../common"
import "../controls"

Column {
    id: root

    property bool animationActive: true
    property bool _listOpen: false

    // package entries scroll inside a capped list with no dividers, so they
    // track the text rather than the row grid every other settings row snaps to
    readonly property int _entryH: Math.max(22, Settings.capHeight + 8)

    readonly property bool _packagesAvailable: Updates.count > 0
        && !Updates.lastFailed && Updates.packages.length > 0

    on_PackagesAvailableChanged: if (!_packagesAvailable) _listOpen = false

    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "SYSTEM PACKAGES"; first: true }
    SettingsCard {
        UpdateStatusCard {
            animationActive: root.animationActive
            glyph: Updates.isChecking ? "󰓦" : Updates.lastFailed ? "󰀦" : Updates.icon
            title: "System packages"
            status: Updates.statusText
            meta: Updates.managerLabel
            detail: Updates.lastFailed ? Updates.lastError
                : Updates.aurCount > 0
                    ? Updates.repoCount + " from repos, " + Updates.aurCount + " from the AUR"
                        + (Updates.lastCheckLabel.length > 0 ? " · " + Updates.lastCheckLabel : "")
                    : Updates.lastCheckLabel
            detailError: Updates.lastFailed
            statusColor: Updates.lastFailed ? Theme.warning
                : Updates.isChecking ? Theme.accent
                : Updates.enabled && Updates.ready && Updates.count === 0 ? Theme.success
                : Updates.count > 0 ? Theme.accent : Theme.subtext
            busy: Updates.isChecking

            primaryLabel: !SystemTools.ready ? "Detecting…"
                : !Updates.supported ? "Unavailable"
                : !ShellSettings.updatesWidget ? "Off"
                : Updates.isChecking ? "Checking…" : "Check"
            primaryGlyph: "󰓦"
            primaryEnabled: SystemTools.ready && Updates.supported
                && ShellSettings.updatesWidget && !Updates.isChecking
            onPrimaryTriggered: Updates.refresh()
        }
        ControlRow {
            glyph: "󰏗"
            title: "Pending packages"
            valueText: Updates.packages.length < Updates.count
                ? Updates.packages.length + " of " + Updates.count : String(Updates.count)
            visible: root._packagesAvailable
            expandable: true
            expanded: root._listOpen && root._packagesAvailable
            onExpandToggled: root._listOpen = !root._listOpen
            onActivated: root._listOpen = !root._listOpen
        }
        CollapsibleSection {
            expanded: root._listOpen && root._packagesAvailable
            Item {
                width: parent ? parent.width : 0
                height: Math.min(_packages.contentHeight, 240)

                ShellListView {
                    id: _packages
                    anchors.fill: parent
                    interactive: contentHeight > height
                    spacing: 0
                    model: root._listOpen && root._packagesAvailable
                        ? Updates.packages : []

                    delegate: Item {
                        id: _pkg
                        required property var modelData
                        width: parent ? parent.width : 0
                        height: root._entryH
                        ShellText {
                            anchors.left: parent.left
                            anchors.leftMargin: 42
                            anchors.right: _ver.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: _pkg.modelData.name
                            elide: Text.ElideRight
                            color: Theme.withAlpha(Theme.text, 0.80)
                            font.pixelSize: Settings.fontLabel
                        }
                        ShellText {
                            id: _ver
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: _pkg.modelData.to + (_pkg.modelData.aur ? "  AUR" : "")
                            color: Theme.withAlpha(Theme.subtext,
                                _pkg.modelData.aur ? 0.75 : 0.55)
                            font.pixelSize: Settings.fontCaption
                        }
                    }
                }

                ListEdgeLines {
                    anchors.fill: parent
                    list: _packages
                }
            }
        }
        ToggleRow {
            glyph: "󰚰"; label: "Track package updates"
            description: "Show pending count in bar"
            key: "updatesWidget"
            available: !SystemTools.ready || Updates.supported
            dependsNote: "No package manager"
        }
        ToggleRow {
            visible: SystemTools.packageFamily === "pacman"
                && Updates.aurHelperAvailable
            glyph: "󰮯"; label: "Include AUR packages"
            description: "Query "
                + (SystemTools.hasParu ? "paru" : "yay")
                + " for foreign package updates"
            key: "updatesIncludeAur"
        }
        HintText { text: "Checks are read-only and never install updates." }
    }
}
