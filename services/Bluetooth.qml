pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth as Bt

Singleton {
    id: root

    readonly property var adapter: Bt.Bluetooth.defaultAdapter
    readonly property bool available: adapter !== null
    readonly property bool enabled:   adapter ? adapter.enabled : false

    // Backend models can be momentarily empty while BlueZ re-enumerates.
    readonly property var _devices: (adapter && adapter.devices)
        ? (adapter.devices.values || []) : []

    readonly property int connectedCount: {
        let n = 0
        for (let i = 0; i < _devices.length; i++)
            if (_devices[i] && _devices[i].connected) n++
        return n
    }

    readonly property string connectedName: {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.connected) return root.deviceLabel(d)
        }
        return ""
    }

    function deviceLabel(device): string {
        if (!device) return "Unknown"
        return SafeText.singleLineText(
            device.deviceName || device.name || device.address || "Unknown", 128) || "Unknown"
    }

    // BlueZ can briefly advertise batteryAvailable before the percentage
    // arrives. Keep the conversion and validation in one place so every UI
    // surface falls back to its non-battery label instead of showing NaN%.
    function batteryPercent(device): int {
        if (!device || !device.batteryAvailable) return -1
        const raw = Number(device.battery)
        if (!isFinite(raw) || raw < 0) return -1
        return Math.max(0, Math.min(100, Math.round(raw > 1 ? raw : raw * 100)))
    }

    readonly property int connectedBattery: {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.connected) return root.batteryPercent(d)
        }
        return -1
    }

    function _sortedDevices(): var {
        const list = root._devices.slice()
        list.sort((a, b) => {
            if (!a || !b) return 0
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.paired !== b.paired)       return a.paired ? -1 : 1
            const an = (a.deviceName || a.name || "").toLowerCase()
            const bn = (b.deviceName || b.name || "").toLowerCase()
            return an < bn ? -1 : (an > bn ? 1 : 0)
        })
        return list
    }

    // membership and the fields the sort above actually reads — not pairing/trusted/state/
    // battery, which a row shows straight off the retained device object underneath and so
    // already update live without the array itself being republished
    function _devicesKey(list: var): string {
        return list.map(d => [d.address, d.connected, d.paired, (d.deviceName || d.name || "")]
            .join("")).join("")
    }

    property string _devicesKeySnapshot: ""
    // set by BluetoothList while a device's details panel is open: a republish landing then
    // would replace the array and tear down every delegate — including that open row — the
    // same hazard Network.setWifiListFrozen guards against for the wifi list's details panel
    property bool _devicesFrozen: false
    function setDevicesFrozen(frozen: bool): void {
        if (root._devicesFrozen === frozen) return
        root._devicesFrozen = frozen
        if (!frozen) root._refreshDevices()
    }

    // devices used to be `readonly property var: {...sort...}`, a binding that reruns —
    // new array, new ListView model reference — the instant any tracked device's connected/
    // paired/name changes, which tears down and rebuilds every delegate even though that's
    // rarer here than wifi's continuous signal churn. Polling on a bounded timer and only
    // publishing when the structural key changes keeps an unrelated device's state flip from
    // rebuilding a row whose details panel is open, mirroring Network.wifiNetworks.
    function _refreshDevices(): void {
        if (root._devicesFrozen) return
        const next = root._sortedDevices()
        const key = root._devicesKey(next)
        if (key === root._devicesKeySnapshot) return
        root._devicesKeySnapshot = key
        root.devices = next
    }

    property var devices: []

    Timer {
        id: _devicesPoll
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root._scanRequested
        onTriggered: root._refreshDevices()
    }

    function toggle(): void {
        if (adapter) adapter.enabled = !adapter.enabled
    }

    property bool _scanRequested: false
    function setScan(on: bool): void {
        const want = !!(on && adapter && adapter.enabled)
        // coalesce: onOpenChanged and Component.onCompleted can request the same state in one pass and BlueZ answers "Operation already in progress"
        _scanRequested = want
        if (!_scanSync.running) _scanSync.restart()
    }

    Timer {
        id: _scanSync
        interval: 0
        onTriggered: {
            if (!root.adapter) return
            const want = root._scanRequested && root.adapter.enabled
            if (root.adapter.discovering !== want) root.adapter.discovering = want
        }
    }

    // dispatch by address through the raw _devices array to reach the live C++ object, not a sorted JS copy
    function connectDevice(address: string): void {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { d.connect(); return }
        }
    }
    function disconnectDevice(address: string): void {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { d.disconnect(); return }
        }
    }
    function pairDevice(address: string): void {
        if (adapter) adapter.pairable = true
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { d.pair(); return }
        }
    }
    function cancelPair(address: string): void {
        for (let i = 0; i < _devices.length; i++) {
            const d = _devices[i]
            if (d && d.address === address) { d.cancelPair(); return }
        }
    }

    // "Open bluetooth manager…" launches a user-declared command template
    // (ShellSettings.btEditCommand) through the same TemplateLauncher WifiProfile's
    // editor escape hatch uses. The template carries no {placeholder} — nothing to
    // look up first, so a click launches immediately with no query round-trip.
    TemplateLauncher {
        id: _managerLauncher
        template: ShellSettings.btEditCommand
    }
    readonly property bool managerAvailable: _managerLauncher.available
    // surfaced so BluetoothDetails can report a failed launch (cooldown, tool vanished
    // mid-session) instead of a click that silently does nothing, same as WifiProfile.lastError
    readonly property string lastError: _managerLauncher.lastError
    function launchManager(): void {
        _managerLauncher.launch()
    }
}
