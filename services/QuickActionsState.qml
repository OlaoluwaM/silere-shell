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

        function toggle(): void {
            if (root.open) { root.close(); return }
            root.barBottom = Metrics.barAtBottom
            root.openUnanchored()
        }
        function close(): void { root.close() }

        // the same toggle the panel row and bar pill use, so a timed run still arms from the saved duration
        function dnd(): string {
            Notifications.toggleDnd()
            return Notifications.dnd ? "on" : "off"
        }

        function nightLight(): string {
            // the optional-tool scan runs at startup; before it lands no tool looks installed
            if (!SystemTools.ready) return "error: still looking for a night light tool"
            if (!NightLight.toolAvailable)
                return "error: night light needs hyprsunset"
            NightLight.toggle()
            return NightLight.enabled ? "on" : "off"
        }

        // the backend answers out of process, so the profile that landed is not readable yet
        function powerMode(): string {
            if (!PowerProfiles.available)
                return "error: power modes need powerprofilesctl or asusctl"
            const next = PowerProfiles.cycle()
            return next.length > 0 ? next : "error: a power profile change is already in flight"
        }

        function wifi(): string {
            if (!root.wifiControllable)
                return Network.wifiHardBlocked
                    ? "error: the Wi-Fi radio is blocked in hardware"
                    : "error: no Wi-Fi device the shell can control"
            // the radios answer over dbus, so report the state that was asked for
            const next = !Network.wifiEnabled
            Network.toggleWifi()
            return next ? "on" : "off"
        }

        function bluetooth(): string {
            if (!root.btControllable) return "error: no Bluetooth adapter"
            const next = !Bluetooth.enabled
            Bluetooth.toggle()
            return next ? "on" : "off"
        }
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
