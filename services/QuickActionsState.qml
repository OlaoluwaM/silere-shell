pragma Singleton

import QtQuick
import Quickshell.Io
import "../config"

AnchoredPopupState {
    id: root

    controlSurface: true
    blocksBarHints: true
    property bool barBottom: false

    function toggleAt(x: real, screen, bottom: bool, source): void {
        if (open) { close(); return }
        barBottom = bottom
        openAt(x, screen, source)
    }

    IpcHandler {
        target: "quickActions"

        function toggle(): string {
            if (root.open) { root.close(); return "ok" }
            root.barBottom = Metrics.barAtBottom
            root.openUnanchored()
            return root.open ? "ok"
                : "error: quick actions stay closed while the session is idle or the overview is open"
        }
        function close(): void { root.close() }

        // the same toggle the panel row and bar pill use, so a timed run still arms from the saved duration
        function dnd(): string {
            Notifications.toggleDnd()
            return Notifications.dnd ? "on" : "off"
        }

        function nightLight(): string { return root._nightLightReply() }
        function powerMode(): string { return root._powerModeReply() }
        function wifi(): string { return root._wifiReply() }
        function bluetooth(): string { return root._bluetoothReply() }
    }

    // Wi-Fi and Bluetooth publish no "probing finished" signal, and an empty device list looks the
    // same before enumeration as after; a keybind fired right at login gets "still starting" instead
    property bool _settled: false
    Timer {
        interval: 3000
        running: true
        onTriggered: root._settled = true
    }

    function _nightLightReply(): string {
        // the optional-tool scan runs at startup; before it lands no tool looks installed
        if (!SystemTools.ready) return "error: still looking for a night light tool"
        if (!NightLight.toolAvailable)
            return "error: night light needs hyprsunset"
        // toggle() flips enabled synchronously, so an unchanged value means it returned early
        const before = NightLight.enabled
        NightLight.toggle()
        if (NightLight.enabled === before)
            return "error: a night light change is already in progress"
        return NightLight.enabled ? "on" : "off"
    }

    // the backend answers out of process, so the profile that landed is not readable yet
    function _powerModeReply(): string {
        if (!SystemTools.ready && !PowerProfiles.available)
            return "error: still looking for a power mode tool"
        switch (PowerProfiles.cycleBlockedBy()) {
        case "unavailable": return "error: power modes need powerprofilesctl or asusctl"
        case "busy":        return "error: a power mode change is already in flight"
        case "loading":
            PowerProfiles.load()
            return "error: power modes are loading now; try again"
        case "single":      return "error: only one power mode is available"
        case "unlisted":    return "error: the current power mode is not one the backend lists"
        }
        const next = PowerProfiles.cycle()
        return next.length > 0 ? next : "error: the power mode could not be changed"
    }

    function _wifiReply(): string {
        if (!root.wifiControllable) {
            if (Network.wifiHardBlocked) return "error: the Wi-Fi radio is blocked in hardware"
            if (!root._settled) return "error: Wi-Fi is still starting; try again"
            return "error: no Wi-Fi device the shell can control"
        }
        // the radios answer over dbus, so report the state that was asked for
        const next = !Network.wifiEnabled
        Network.toggleWifi()
        return next ? "on" : "off"
    }

    function _bluetoothReply(): string {
        if (!root.btControllable) {
            if (Bluetooth.hardBlocked) return "error: the Bluetooth adapter is blocked in hardware"
            if (!root._settled) return "error: Bluetooth is still starting; try again"
            return "error: no Bluetooth adapter"
        }
        const next = !Bluetooth.enabled
        Bluetooth.toggle()
        return next ? "on" : "off"
    }

    // a hard-blocked radio refuses every write, so a row offering it would re-issue two doomed requests per tap and never change
    readonly property bool wifiControllable: Network.toolAvailable && Network.hasWifiDevice
        && !Network.wifiHardBlocked
    readonly property bool btControllable: Bluetooth.available && !Bluetooth.hardBlocked
    readonly property bool airplaneAvailable: wifiControllable || btControllable
    readonly property bool radiosOn: (wifiControllable && Network.wifiEnabled)
        || (btControllable && Bluetooth.enabled)

    property bool _airplaneLatched: false
    property bool _priorWifi: false
    property bool _priorBt: false

    // with nothing latched there is no prior state to honour, so both come back
    function _airplaneRestore(latched: bool, priorWifi: bool, priorBt: bool): var {
        return latched ? { wifi: priorWifi, bt: priorBt } : { wifi: true, bt: true }
    }

    function toggleAirplane(): void {
        if (radiosOn) {
            _priorWifi = wifiControllable && Network.wifiEnabled
            _priorBt = btControllable && Bluetooth.enabled
            _airplaneLatched = true
            if (_priorWifi) Network.toggleWifi()
            if (_priorBt) Bluetooth.toggle()
            return
        }
        const want = _airplaneRestore(_airplaneLatched, _priorWifi, _priorBt)
        _airplaneLatched = false
        if (wifiControllable && want.wifi && !Network.wifiEnabled) Network.toggleWifi()
        if (btControllable && want.bt && !Bluetooth.enabled) Bluetooth.toggle()
    }

    // a chord press goes through the same latch-aware toggle the row and pill
    // use, so restore still brings back only the radios airplane itself cut
    IpcHandler {
        target: "airplane"

        function toggle(): void { if (root.airplaneAvailable) root.toggleAirplane() }
    }
}
