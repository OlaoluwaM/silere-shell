pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth as Bt
import "../../config"
import "../../services"
import "../common"
import "controls"

Item {
    id: root

    property bool open: false

    width: parent ? parent.width : 0
    implicitHeight: _col.implicitHeight

    property string _armedAddr: ""
    Timer { id: _disarmTimer; interval: 3000; onTriggered: root._armedAddr = "" }

    // only one device's details panel is open at a time, matched by address rather than
    // index/identity — Bluetooth.devices resorts (and rebuilds delegates) on any device's
    // connected/paired change, but this lives on root, not the delegate, so it survives that.
    // Freezing Bluetooth's published list while this is set stops that resort from tearing
    // the open row down mid-view (mirrors Network.setWifiListFrozen for the same reason).
    property string _detailsAddr: ""
    on_DetailsAddrChanged: Bluetooth.setDevicesFrozen(root._detailsAddr !== "")

    property bool _searchLapsed: false
    Timer {
        interval: 10000
        running: root.open && Bluetooth.available && Bluetooth.enabled
            && Bluetooth.devices.length === 0 && !Idle.isIdle
        onRunningChanged: if (running) root._searchLapsed = false
        onTriggered: root._searchLapsed = true
    }

    function _syncScanState(): void {
        Bluetooth.setScan(root.open && Bluetooth.available && Bluetooth.enabled && !Idle.isIdle)
        if (!Bluetooth.available || !Bluetooth.enabled) {
            _disarmTimer.stop()
            root._armedAddr = ""
        }
    }

    onOpenChanged: {
        _syncScanState()
        if (!open) { _disarmTimer.stop(); root._armedAddr = ""; root._detailsAddr = "" }
    }
    Component.onCompleted: _syncScanState()
    Component.onDestruction: { Bluetooth.setScan(false); Bluetooth.setDevicesFrozen(false) }

    Connections {
        target: Bluetooth
        function onAvailableChanged() { root._syncScanState() }
        function onEnabledChanged() { root._syncScanState() }
        // the row whose drawer this pointed at no longer exists in Bluetooth.devices —
        // Bluetooth._purgeRemovedDevice already dropped it from the published array in this
        // same call, so clearing here can't race a stale republish putting it back
        function onDeviceRemoved(address) {
            if (root._detailsAddr === address) root._detailsAddr = ""
        }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() { root._syncScanState() }
    }

    function _devGlyph(icon): string {
        const s = (icon || "").toLowerCase()
        if (s.indexOf("headset") >= 0 || s.indexOf("headphone") >= 0 || s.indexOf("audio") >= 0) return "󰋋"
        if (s.indexOf("mouse") >= 0)    return "󰍽"
        if (s.indexOf("keyboard") >= 0) return "󰌌"
        if (s.indexOf("phone") >= 0)    return "󰏳"
        if (s.indexOf("speaker") >= 0)  return "󰓃"
        if (s.indexOf("watch") >= 0)    return "󰖉"
        return "󰂱"
    }

    Column {
        id: _col
        width: parent.width
        spacing: 0

        ShellText {
            visible: root.open && (!Bluetooth.available || !Bluetooth.enabled || Bluetooth.devices.length === 0)
            width: parent.width
            height: Metrics.rowHeightFor(32)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: !Bluetooth.available ? "Bluetooth unavailable"
                : !Bluetooth.enabled   ? "Bluetooth is off"
                : root._searchLapsed   ? "No devices found"
                :                        "Searching for devices…"
            color: Theme.withAlpha(Theme.subtext, 0.5)
            font.pixelSize: Settings.fontLabel
        }

        ShellListView {
            id: _list
            width: parent.width
            height: Math.min(contentHeight, 240)
            visible: root.open && Bluetooth.available && Bluetooth.enabled && Bluetooth.devices.length > 0
            interactive: contentHeight > height
            spacing: 0
            // Same ScriptModel treatment as WifiList, but with NO objectProp: these
            // values are live BluetoothDevice objects, and ScriptModel's fallback
            // variant equality on QObject* is pointer identity -- exactly the right
            // key for stable device objects. A republish (resort, or the purge on
            // device removal) becomes row moves/removals instead of a model reset,
            // so scroll position and delegates survive it.
            model: ScriptModel {
                values: root.open ? Bluetooth.devices : []
            }

            delegate: Column {
                id: _entry
                required property var modelData
                required property int index
                width: _list.width
                spacing: 0

                readonly property bool _detailsOpen: root._detailsAddr === modelData.address && modelData.connected

                InlineOptionRow {
                    id: _row
                    width: parent.width

                    readonly property bool   _armed: root._armedAddr === _entry.modelData.address && _entry.modelData.connected
                    readonly property int _batt: Bluetooth.batteryPercent(_entry.modelData)
                    readonly property string _state:
                        _armed ? "Disconnect?"
                        : _entry.modelData.pairing ? "Cancel?"
                        : _entry.modelData.state === Bt.BluetoothDeviceState.Connecting    ? "Connecting…"
                        : _entry.modelData.state === Bt.BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                        : _entry.modelData.connected ? (_batt >= 0 ? _batt + "%" : "Connected")
                        : _entry.modelData.paired    ? "Paired"
                        : "Pair"

                    glyph: root._devGlyph(_entry.modelData.icon)
                    label: Bluetooth.deviceLabel(_entry.modelData)
                    status: _state
                    selected: _entry.modelData.connected
                    warning: _armed || _entry.modelData.pairing
                    // the body tap already means connect/disconnect for this row, so
                    // details live behind the chevron's separate hit zone instead
                    expandable: _entry.modelData.connected
                    expanded: _entry._detailsOpen

                    function _activate(): void {
                        const addr = _entry.modelData.address
                        if (_entry.modelData.pairing) {
                            Bluetooth.cancelPair(addr)
                        } else if (_entry.modelData.connected) {
                            if (root._armedAddr === addr) {
                                root._armedAddr = ""
                                _disarmTimer.stop()
                                Bluetooth.disconnectDevice(addr)
                            } else {
                                root._armedAddr = addr
                                _disarmTimer.restart()
                            }
                        } else if (_entry.modelData.paired) {
                            Bluetooth.connectDevice(addr)
                        } else {
                            Bluetooth.pairDevice(addr)
                        }
                    }
                    onTriggered: _activate()
                    onExpandToggled: root._detailsAddr = (root._detailsAddr === _entry.modelData.address)
                        ? "" : _entry.modelData.address
                    // expanded is bound to _entry._detailsOpen, which already goes false the
                    // instant this device disconnects; without this, _detailsAddr would keep
                    // pointing at it and the panel would silently reopen on a later reconnect
                    onExpandedChanged: if (!expanded && root._detailsAddr === _entry.modelData.address)
                        root._detailsAddr = ""
                }

                Item {
                    width: parent.width
                    height: _entry._detailsOpen ? _details.implicitHeight : 0
                    clip: true
                    visible: height > 0.5
                    Disclosure on height { expanded: _entry._detailsOpen }

                    BluetoothDetails {
                        id: _details
                        width: parent.width
                        device: _entry.modelData
                    }
                }
            }
        }
    }

    // the card's own divider sits in this gutter one px past the list: land the cue on it
    ListEdgeLines {
        x: 14; y: _col.y + _list.y
        width: Math.max(0, parent.width - 28); height: _list.height + 1
        visible: _list.visible
        list: _list
    }
}
