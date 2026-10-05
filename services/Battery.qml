pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "../config"

Singleton {
    id: root

    readonly property bool upowerReady: UPower.displayDevice && UPower.displayDevice.ready
    readonly property bool available: upowerReady && UPower.displayDevice.isPresent
    // quickshell scales upower's 0-100 to 0-1 as it reads it
    readonly property real _raw: upowerReady ? UPower.displayDevice.percentage : 0

    function normalizedPercent(raw): real {
        const value = Number(raw)
        if (!isFinite(value) || value <= 0) return 0
        return Math.max(0, Math.min(100, value * 100))
    }

    readonly property real pct: root.normalizedPercent(_raw)
    readonly property bool onBattery: available ? UPower.onBattery : false
    readonly property int  _critPct: Math.max(5, Math.round(ShellSettings.batteryLowThreshold / 2))
    // pct==0 is UPower's uninitialised reading at startup; would fire a bogus critical alert
    readonly property bool _validReading: available && pct > 0
    readonly property bool low: _validReading && pct < ShellSettings.batteryLowThreshold && onBattery
    readonly property bool critical: _validReading && pct < _critPct && onBattery
    readonly property bool charging: available && !onBattery
    readonly property bool full:     available && pct >= 99
    readonly property int pulseDuration: critical ? Motion.ms(650) : Motion.ms(2000)
    property real alertPulse: 0

    readonly property color iconColor: {
        if (!available || !_validReading)             return Theme.subtext
        if (charging)                                 return full ? Theme.success : Theme.accent
        if (pct < _critPct)                           return Theme.error
        if (pct < ShellSettings.batteryLowThreshold)  return Theme.warning
        return Theme.accent
    }

    readonly property string icon: {
        if (!available || !_validReading)  return "󰂎"
        if (!onBattery) {
            if (pct >= 95)   return "󰂅"
            if (pct >= 90)   return "󰂋"
            if (pct >= 80)   return "󰂊"
            if (pct >= 70)   return "󰢞"
            if (pct >= 60)   return "󰂉"
            if (pct >= 50)   return "󰢝"
            if (pct >= 40)   return "󰂈"
            if (pct >= 30)   return "󰂇"
            if (pct >= 20)   return "󰂆"
            return "󰢜"
        }
        if (pct >= 95)   return "󰁹"
        if (pct >= 90)   return "󰂂"
        if (pct >= 80)   return "󰂁"
        if (pct >= 70)   return "󰂀"
        if (pct >= 60)   return "󰁿"
        if (pct >= 50)   return "󰁾"
        if (pct >= 40)   return "󰁽"
        if (pct >= 30)   return "󰁼"
        if (pct >= 20)   return "󰁻"
        return "󰁺"
    }

    readonly property string label: _validReading ? `${Math.round(pct)}%` : ""

    // charge_control_end_threshold is a laptop-vendor sysfs knob (thinkpad_acpi, ideapad,
    // etc), so it's a plain, possibly-missing file rather than anything UPower exposes.
    // Detected once via a bounded glob, same idiom Brightness uses for backlight devices;
    // absent/unreadable leaves chargeLimit at -1, which callers treat as "no such thing".
    property string _chargeLimitPath: ""
    property bool   _chargeLimitProbed: false
    property int    _chargeLimitRaw: -1
    readonly property int chargeLimit: root._chargeLimitRaw

    function _probeChargeLimit(): void {
        if (root._chargeLimitProbed) return
        root._chargeLimitProbed = true
        _chargeLimitProbe.running = true
    }

    Component.onCompleted: root._probeChargeLimit()

    BoundedProcess {
        id: _chargeLimitProbe
        timeoutMs: 3000
        command: ["bash", "-c",
            "for f in /sys/class/power_supply/BAT*/charge_control_end_threshold; do " +
            "  [ -r \"$f\" ] && printf '%s\\n' \"$f\" && exit 0; " +
            "done; exit 1"]
        stdout: StdioCollector { id: _chargeLimitProbeOut }
        onExited: (code) => {
            root._chargeLimitPath = (code === 0 && !_chargeLimitProbe.timedOut)
                ? (_chargeLimitProbeOut.text || "").trim() : ""
            if (root._chargeLimitPath.length === 0) root._chargeLimitRaw = -1
        }
    }

    FileView {
        id: _chargeLimitFile
        path: root._chargeLimitPath
        watchChanges: root._chargeLimitPath.length > 0
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: {
            const v = parseInt((_chargeLimitFile.text() || "").trim())
            root._chargeLimitRaw = (!isNaN(v) && v > 0 && v <= 100) ? v : -1
        }
        onLoadFailed: root._chargeLimitRaw = -1
    }

    readonly property real   timeToEmpty: upowerReady ? UPower.displayDevice.timeToEmpty : 0
    readonly property real   timeToFull:  upowerReady ? UPower.displayDevice.timeToFull  : 0
    readonly property string timeLabel: {
        const secs = onBattery ? timeToEmpty : timeToFull
        if (!available || secs <= 0) return ""
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        const time = h > 0 ? `${h}h ${m}m` : `${m}m`
        return onBattery ? time : `+ ${time}`
    }

    // a charge limit (Lenovo conservation mode, ThinkPad thresholds) parks the battery on AC
    readonly property bool held: available && !onBattery
        && UPower.displayDevice.state === UPowerDeviceState.PendingCharge

    readonly property string statusLabel: {
        if (!available)  return ""
        if (!onBattery)  return full ? "charged" : held ? "not charging" : "charging"
        return "discharging"
    }

    // consumers: BatteryWidget's opacity dip, BarUnderline's glow (underlineBattGlow),
    // and the home page's vitals tile -- with none of them present nothing ever reads
    // alertPulse, so there is nothing to spend per-frame bar damage animating for
    readonly property bool _alertConsumerVisible: ShellSettings.barWidgetPlaced("battery")
        || ShellSettings.underlineBattGlow
        || MenuState.homeActive

    // settle, same idiom as WorkspaceUrgentTick's urgent tick: hours on battery under the
    // low threshold would otherwise pulse the whole time. Re-arm on each threshold
    // crossing (low turning true, and again when critical does) so the alert still
    // announces a worsening state, then rest at the pulse's floor.
    property bool _alertSettled: true
    onLowChanged:      if (low)      root._alertSettled = false
    onCriticalChanged: if (critical) root._alertSettled = false

    Timer {
        interval: 15000
        running: root.low && !root._alertSettled && !Idle.isIdle && root._alertConsumerVisible
        onTriggered: root._alertSettled = true
    }

    PulseLoop {
        target:         root
        targetProperty: "alertPulse"
        duration:       root.pulseDuration
        active:         root.low && !Idle.isQuiet && root._alertConsumerVisible && !root._alertSettled
    }
}
