pragma Singleton

// Ownership split: a Nix-managed `hyprsunset.service` systemd user unit owns
// the daemon's lifecycle and runs its own scheduled day/night temperature
// staircase. This singleton never spawns or kills hyprsunset itself — it is
// only a control surface that starts/stops the unit and mirrors its state,
// so the shell and systemd are never racing to own the same process.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string _unit: "hyprsunset.service"

    property bool enabled:        false
    property string lastError:    ""
    readonly property bool toolAvailable: SystemTools.hasHyprsunset
    readonly property int  temperature: ShellSettings.nightLightTemp

    property bool _geoResolved: false
    property real _autoLat: 0
    property real _autoLon: 0
    readonly property real _useLat: _geoResolved ? _autoLat : 45.0
    readonly property real _useLon: _geoResolved ? _autoLon
                                                 : -(new Date().getTimezoneOffset()) / 4
    readonly property string locationLabel:
        Math.abs(_useLat).toFixed(0) + "°" + (_useLat >= 0 ? "N" : "S")

    property int _solarTick: 0
    readonly property real _declRad: {
        root._solarTick
        const d = new Date()
        const n = Math.floor((d - new Date(d.getFullYear(), 0, 0)) / 86400000)
        return 23.44 * Math.sin(2 * Math.PI * (n - 81) / 365) * Math.PI / 180
    }
    readonly property real _elevation: {
        root._solarTick
        const d    = new Date()
        const decl = root._declRad
        const h    = ((d.getUTCHours() + d.getUTCMinutes() / 60 + root._useLon / 15 - 12) * 15) * Math.PI / 180
        const phi  = root._useLat * Math.PI / 180
        return Math.asin(Math.sin(phi) * Math.sin(decl) +
                         Math.cos(phi) * Math.cos(decl) * Math.cos(h)) * 180 / Math.PI
    }
    readonly property int suggestedTemp: {
        const elev = root._elevation
        if (elev >= 6)  return 6500
        if (elev <= -6) return 3000
        return Math.round((3000 + 3500 * (elev + 6) / 12) / 100) * 100
    }

    readonly property real _solarNoon: {
        root._solarTick
        return 12 - root._useLon / 15 - (new Date()).getTimezoneOffset() / 60
    }
    readonly property real _halfDay: {
        const c = Math.max(-1, Math.min(1, -Math.tan(root._useLat * Math.PI / 180) * Math.tan(root._declRad)))
        return Math.acos(c) * 180 / Math.PI / 15
    }
    readonly property real sunriseHour: _solarNoon - _halfDay
    readonly property real sunsetHour:  _solarNoon + _halfDay
    readonly property real _nowHour: { root._solarTick; const d = new Date(); return d.getHours() + d.getMinutes() / 60 }
    readonly property bool isDaytime: _halfDay > 0 && _nowHour >= sunriseHour && _nowHour <= sunsetHour
    readonly property real dayProgress:
        _halfDay <= 0 ? -1 : Math.max(0, Math.min(1, (_nowHour - sunriseHour) / (sunsetHour - sunriseHour)))
    readonly property real nightProgress: {
        if (_halfDay <= 0) return 0
        const nightDur = 24 - (sunsetHour - sunriseHour)
        if (nightDur <= 0) return 0
        const afterSunset = (_nowHour - sunsetHour + 24) % 24
        return Math.max(0, Math.min(1, afterSunset / nightDur))
    }

    function _fmtHour(h: real): string {
        if (!isFinite(h)) return "--:--"
        let hh = Math.floor(((h % 24) + 24) % 24)
        let mm = Math.round((h - Math.floor(h)) * 60)
        if (mm >= 60) { mm -= 60; hh = (hh + 1) % 24 }
        return (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm
    }
    readonly property string sunriseLabel: _halfDay <= 0 ? "--:--" : _fmtHour(sunriseHour)
    readonly property string sunsetLabel:  _halfDay <= 0 ? "--:--" : _fmtHour(sunsetHour)

    function _dur(mins: real): string {
        const m = Math.max(0, Math.round(mins))
        const hh = Math.floor(m / 60), mm = m % 60
        return hh > 0 ? (hh + "h " + (mm < 10 ? "0" : "") + mm + "m") : (mm + "m")
    }
    readonly property string phaseLabel: {
        root._solarTick
        if (_halfDay <= 0)  return "polar night"
        if (_halfDay >= 12) return "midnight sun"
        if (isDaytime)            return _dur((sunsetHour - _nowHour) * 60) + " of daylight"
        if (_nowHour < sunriseHour) return "sunrise in " + _dur((sunriseHour - _nowHour) * 60)
        return "sunrise in " + _dur((24 - _nowHour + sunriseHour) * 60)
    }

    readonly property bool recommended: _elevation < 0
    readonly property string recommendLabel: {
        // this lands in the same row slot as "Not connected" and "Quiet hours", which are
        // sentence case; phaseLabel is a caption inside the arc and stays lowercase
        if (_halfDay >= 12)  return ""
        if (recommended)     return "Recommended"
        if (_elevation < 12) return "From " + sunsetLabel
        return ""
    }

    function _parseCoord(s: string): void {
        const m = /^([+-]\d{2})(\d{2})(\d{2})?([+-]\d{3})(\d{2})(\d{2})?$/.exec((s || "").trim())
        if (!m) return
        const latSign = m[1].charAt(0) === "-" ? -1 : 1
        const lonSign = m[4].charAt(0) === "-" ? -1 : 1
        root._autoLat = latSign * (Math.abs(Number(m[1])) + Number(m[2]) / 60 + (m[3] ? Number(m[3]) : 0) / 3600)
        root._autoLon = lonSign * (Math.abs(Number(m[4])) + Number(m[5]) / 60 + (m[6] ? Number(m[6]) : 0) / 3600)
        root._geoResolved = true
    }

    BoundedProcess {
        id: _geoProc
        running: false
        timeoutMs: 5000
        command: ["bash", "-c",
            "tz=\"$(timedatectl show -p Timezone --value 2>/dev/null)\"; " +
            "[ -z \"$tz\" ] && tz=\"$(readlink -f /etc/localtime 2>/dev/null | sed -n 's#.*/zoneinfo/##p')\"; " +
            "[ -z \"$tz\" ] && [ -r /etc/timezone ] && tz=\"$(cat /etc/timezone)\"; " +
            "[ -z \"$tz\" ] && exit 0; " +
            "for f in /usr/share/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone.tab; do " +
            "  [ -r \"$f\" ] || continue; " +
            "  c=\"$(awk -v z=\"$tz\" 'BEGIN{FS=\"\\t\"} $0 !~ /^#/ && $3==z {print $2; exit}' \"$f\")\"; " +
            "  [ -n \"$c\" ] && { printf '%s\\n' \"$c\"; break; }; " +
            "done"]
        stdout: StdioCollector { id: _geoOut }
        onExited: root._parseCoord(_geoOut.text)
    }

    Timer {
        interval: 60000; repeat: true
        running: root.toolAvailable && ShellSettings.nightLightAuto && root.enabled && !Idle.isIdle
        onTriggered: root._solarTick++
    }
    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root._solarTick++ }
    }
    Connections {
        target: Idle
        function onIsIdleChanged() {
            if (!Idle.isIdle && ShellSettings.nightLightAuto && root.enabled) root._solarTick++
        }
    }

    onSuggestedTempChanged: {
        if (ShellSettings.nightLightAuto && root.enabled) ShellSettings.nightLightTemp = root.suggestedTemp
    }
    Connections {
        target: ShellSettings
        function onNightLightAutoChanged() {
            if (ShellSettings.nightLightAuto && root.enabled) {
                root._solarTick++
                ShellSettings.nightLightTemp = root.suggestedTemp
            }
        }
    }

    // The unit's own staircase already tracks day/night; a live nudge here only
    // covers the auto-mode recompute above and a manual slider edit, so this is
    // a plain IPC call rather than anything that touches the unit's lifecycle.
    onTemperatureChanged: {
        if (!root.enabled || !root.toolAvailable) return
        Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(root.temperature)])
    }

    function toggle(): void {
        if (!toolAvailable || _toggleProc.running) return
        const goingOn = !root.enabled
        root.lastError = ""
        // set the target temperature before flipping `enabled`: onTemperatureChanged
        // guards on `enabled`, so this update lands while it is still false and
        // never races a hyprctl push ahead of the unit actually starting — the
        // confirmed-active branch in _checkProc.onExited below sends it instead,
        // once the daemon can actually answer IPC
        if (goingOn && ShellSettings.nightLightAuto) {
            root._solarTick++
            ShellSettings.nightLightTemp = root.suggestedTemp
        }
        // only a start initiated here should push the target temp once confirmed;
        // _checkProc.onExited gates on this flag so it never clobbers the unit's
        // own staircase when it merely observes an externally-started unit
        root._pushTempOnConfirm = goingOn
        // optimistic: the row flips the moment it's tapped, and _checkActive
        // (run from onExited below) reconciles it with the unit if the call failed
        root.enabled = goingOn
        _toggleProc.exec(["systemctl", "--user", goingOn ? "start" : "stop", root._unit])
    }

    // a check already in flight when a reconciliation is requested would otherwise
    // just drop it; queue it instead so a post-toggle recheck is never lost
    property bool _recheckPending: false

    // set only by toggle()'s own start, so the confirmed-active branch below
    // pushes the target temp for shell-initiated starts only
    property bool _pushTempOnConfirm: false

    function _checkActive(): void {
        if (!root.toolAvailable) return
        if (_checkProc.running) { root._recheckPending = true; return }
        _checkProc.exec(["systemctl", "--user", "is-active", "--quiet", root._unit])
    }

    // the menu is what instantiates this singleton, so _startGeo's opening edge is already spent by first load
    Component.onCompleted: { _checkActive(); _startGeo() }

    property bool _geoStarted: false
    readonly property bool _geoWanted: toolAvailable && (ShellSettings.nightLightAuto || MenuState.open)
    function _startGeo(): void {
        if (_geoStarted || !_geoWanted) return
        _geoStarted = true
        _geoProc.running = true
    }

    Connections {
        target: SystemTools
        function onReadyChanged() { root._checkActive(); root._startGeo() }
    }
    Connections {
        target: ShellSettings
        function onNightLightAutoChanged() { root._startGeo() }
    }
    Connections {
        target: MenuState
        function onOpenChanged() { root._startGeo() }
    }

    BoundedProcess {
        id: _checkProc
        timeoutMs: 5000
        onExited: (code) => {
            const rerun = root._recheckPending
            root._recheckPending = false
            if (_checkProc.timedOut) {
                root.lastError = "could not check hyprsunset.service"
            } else {
                const wasEnabled = root.enabled
                root.enabled = (code === 0)
                // the unit autostarts with the session and runs its own scheduled
                // staircase, so merely observing it active (e.g. first menu open)
                // must not clobber that — only push once confirmed active for a
                // start this shell itself initiated via toggle()
                if (root.enabled && !wasEnabled && root._pushTempOnConfirm) {
                    Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(root.temperature)])
                    root._pushTempOnConfirm = false
                }
                // a failed start must not leave a stale flag that fires on some
                // later external activation
                if (!root.enabled)
                    root._pushTempOnConfirm = false
            }
            if (rerun) root._checkActive()
        }
    }

    BoundedProcess {
        id: _toggleProc
        timeoutMs: 5000
        stderr: StdioCollector { id: _toggleErr }
        onExited: (code) => {
            if (_toggleProc.timedOut || code !== 0)
                root.lastError = _toggleErr.text.trim().split("\n").pop() || "hyprsunset.service did not respond"
            root._checkActive()
        }
    }

    // catches drift from outside the shell (a manual systemctl call, the unit
    // failing on its own) since only systemd — not this singleton — decides
    // when the daemon actually starts or stops
    Timer {
        interval: 60000; repeat: true
        running: root.toolAvailable
        onTriggered: root._checkActive()
    }
}
