pragma Singleton

// Ownership split: a Nix-managed `sunsetr.service` systemd user unit owns the
// daemon's lifecycle, and the daemon owns the colour temperature: it follows
// the sun or a clock schedule and fades between day and night by itself. This
// singleton never spawns or kills sunsetr. It starts and stops the unit,
// mirrors the daemon's state from `sunsetr status --json --follow`, and reads
// and writes its config with `sunsetr get` and `sunsetr set`, so the shell and
// systemd are never racing to own the same process and the shell never
// competes with the daemon for the display's colour.

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    // QML categories default to Debug; requests and state changes stay at Info, single events at Debug.
    // Periods, temperatures, times, exit codes and unit names only: never command output or a location's value
    readonly property LoggingCategory log: LoggingCategory {
        name: "silere.nightlight"
        defaultLogLevel: LoggingCategory.Info
    }

    readonly property string _unit: "sunsetr.service"

    property bool enabled:        false
    property string lastError:    ""
    readonly property bool available: SystemTools.hasSunsetr

    // what the daemon last said it applied; nothing here is guessed between its events
    property bool _live: false
    property string _period: ""
    property bool _transitioning: false
    property int _currentTemp: 0
    property int _targetTemp: 0
    property var _nextPeriodAt: null
    readonly property bool live: _live
    readonly property string period: _period
    readonly property bool transitioning: _transitioning
    readonly property int currentTemp: _currentTemp
    readonly property int targetTemp: _targetTemp
    readonly property var nextPeriodAt: _nextPeriodAt

    // placeholders until the first read lands; configKnown says whether they came from sunsetr
    property bool _configKnown: false
    property string _mode: "geo"
    property int _nightTemp: 3300
    property int _clockSunsetMin: 19 * 60
    property int _clockSunriseMin: 6 * 60
    property real _configLat: NaN
    property real _configLon: NaN
    readonly property bool configKnown: _configKnown
    readonly property int nightTemp: _nightTemp
    readonly property string schedule: _mode === "geo" ? "sun" : _mode === "static" ? "fixed" : "clock"
    readonly property int clockSunsetMin: _clockSunsetMin
    readonly property int clockSunriseMin: _clockSunriseMin
    readonly property real configLatitude: _configLat
    readonly property real configLongitude: _configLon
    readonly property var _modes: ["geo", "start_at", "finish_by", "center", "static"]
    readonly property var _clockModes: ["start_at", "finish_by", "center"]

    property bool _geoResolved: false
    property real _autoLat: 0
    property real _autoLon: 0
    // the city sunsetr fades for is the one the arc draws; the zone table only stands in without it
    readonly property bool _configCoords: _configKnown && isFinite(_configLat) && isFinite(_configLon)
    readonly property real _useLat: _configCoords ? _configLat : _geoResolved ? _autoLat : 45.0
    readonly property real _useLon: _configCoords ? _configLon
        : _geoResolved ? _autoLon : root.standardOffsetLon(new Date().getFullYear())
    // summer time moves the clock, not the sun: guess the longitude from the standard offset, the later of january's and july's
    function standardOffsetLon(year: int): real {
        return -Math.max(new Date(year, 0, 1).getTimezoneOffset(), new Date(year, 6, 1).getTimezoneOffset()) / 4
    }
    readonly property string locationLabel:
        Math.abs(_useLat).toFixed(0) + "°" + (_useLat >= 0 ? "N" : "S")

    property int _solarTick: 0
    // noaa's fractional-year series: declination in radians and the equation of time in minutes
    readonly property real _yearAngle: {
        root._solarTick
        const d = new Date()
        // counted in utc: a local-midnight difference is an hour short across a dst change
        const n = Math.round((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate())
            - Date.UTC(d.getFullYear(), 0, 0)) / 86400000)
        return 2 * Math.PI / 365 * (n - 1 + (d.getHours() + d.getMinutes() / 60 - 12) / 24)
    }
    readonly property real _declRad: {
        const g = root._yearAngle
        return 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g)
            - 0.006758 * Math.cos(2 * g) + 0.000907 * Math.sin(2 * g)
            - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g)
    }
    readonly property real _eqTimeMin: {
        const g = root._yearAngle
        return 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g)
            - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g))
    }
    readonly property real _elevation: {
        root._solarTick
        const d    = new Date()
        const decl = root._declRad
        const h    = ((d.getUTCHours() + d.getUTCMinutes() / 60 + root._useLon / 15
            + root._eqTimeMin / 60 - 12) * 15) * Math.PI / 180
        const phi  = root._useLat * Math.PI / 180
        return Math.asin(Math.sin(phi) * Math.sin(decl) +
                         Math.cos(phi) * Math.cos(decl) * Math.cos(h)) * 180 / Math.PI
    }

    readonly property real _solarNoon: {
        root._solarTick
        return 12 - root._useLon / 15 - root._eqTimeMin / 60 - (new Date()).getTimezoneOffset() / 60
    }
    // the hour angle, in hours, at which the sun's centre sits at the given elevation;
    // NaN when it never gets there today
    function _hourAngleAt(elevationDeg: real): real {
        const phi = root._useLat * Math.PI / 180
        const decl = root._declRad
        const c = Math.cos((90 - elevationDeg) * Math.PI / 180) / (Math.cos(phi) * Math.cos(decl))
            - Math.tan(phi) * Math.tan(decl)
        return c < -1 || c > 1 ? NaN : Math.acos(c) * 180 / Math.PI / 15
    }
    // -0.833°: refraction plus the sun's radius, so the times match published ones
    readonly property real _halfDay: {
        const phi = root._useLat * Math.PI / 180
        const decl = root._declRad
        const c = Math.max(-1, Math.min(1, Math.cos(90.833 * Math.PI / 180) / (Math.cos(phi) * Math.cos(decl))
            - Math.tan(phi) * Math.tan(decl)))
        return Math.acos(c) * 180 / Math.PI / 15
    }
    readonly property real sunriseHour: _solarNoon - _halfDay
    readonly property real sunsetHour:  _solarNoon + _halfDay
    readonly property real nowHour: { root._solarTick; const d = new Date(); return d.getHours() + d.getMinutes() / 60 }
    // a midnight sun's day wraps past 24:00, which the window below cannot express
    readonly property bool isDaytime: _halfDay >= 12
        || (_halfDay > 0 && nowHour >= sunriseHour && nowHour <= sunsetHour)

    // per sunsetr's src/geo/solar.rs, the evening fade runs from the sun at +10° down to -2° and
    // the morning fade from -2° back up to +10°; a day that never crosses either has no window.
    // The schedule's placeholder says geo before any read, so only a known config draws one
    readonly property real _fadeHighHours: root._hourAngleAt(10)
    readonly property real _fadeLowHours: root._hourAngleAt(-2)
    readonly property bool _fadesToday: root._configKnown && schedule === "sun"
        && isFinite(_fadeHighHours) && isFinite(_fadeLowHours)
    readonly property real eveningFadeStartHour: _fadesToday ? _solarNoon + _fadeHighHours : NaN
    readonly property real eveningFadeEndHour:   _fadesToday ? _solarNoon + _fadeLowHours : NaN
    readonly property real morningFadeStartHour: _fadesToday ? _solarNoon - _fadeLowHours : NaN
    readonly property real morningFadeEndHour:   _fadesToday ? _solarNoon - _fadeHighHours : NaN

    // routed through DateTime.clockText so the times follow the 12h/24h clock setting
    function _fmtHour(h: real): string {
        if (!isFinite(h)) return "--:--"
        const mins = Math.round((((h % 24) + 24) % 24) * 60) % 1440
        return DateTime.clockText(new Date(2000, 0, 1, Math.floor(mins / 60), mins % 60))
    }
    readonly property string sunriseLabel: _halfDay <= 0 ? "--:--" : _fmtHour(sunriseHour)
    readonly property string sunsetLabel:  _halfDay <= 0 ? "--:--" : _fmtHour(sunsetHour)

    function _dur(mins: real): string {
        const m = Math.max(0, Math.round(mins))
        const hh = Math.floor(m / 60), mm = m % 60
        return hh > 0 ? (hh + "h " + mm + "m") : (mm + "m")
    }
    readonly property string phaseLabel: {
        root._solarTick
        if (_halfDay <= 0)  return "polar night"
        if (_halfDay >= 12) return "midnight sun"
        if (isDaytime)            return _dur((sunsetHour - nowHour) * 60) + " of daylight"
        if (nowHour < sunriseHour) return "sunrise in " + _dur((sunriseHour - nowHour) * 60)
        return "sunrise in " + _dur((24 - nowHour + sunriseHour) * 60)
    }

    // this lands in the same row slot as "Not connected", which is sentence case;
    // phaseLabel is a caption inside the arc and stays lowercase
    readonly property string offStatus: {
        if (_halfDay <= 0 || _halfDay >= 12) return ""
        if (nowHour < sunriseHour) return "Sunrise " + sunriseLabel
        if (nowHour >= _solarNoon && _elevation < 12) return "Sunset " + sunsetLabel
        return ""
    }

    // the row's status slot; an empty string while the stream has nothing to say yet,
    // rather than a temperature the daemon never reported
    readonly property string statusLabel: {
        if (!root.enabled) return root.offStatus
        if (!root._live) return ""
        // 6500K is no tint at all, whichever period the daemon is in; a warmer day still shows its number
        if (root._currentTemp >= 6500) return "Neutral"
        return root._currentTemp + "K"
    }
    // the card's header line: what is on screen now, then what comes next and when
    readonly property string detailLabel: {
        if (!root.enabled) return "Off"
        if (!root._live) return ""
        const at = root._nextPeriodAt
        if (root._transitioning) {
            // daylight is the daemon's 6500K, which reads as no tint at all
            const to = root._targetTemp >= 6500 ? "neutral" : root._targetTemp + "K"
            return root.statusLabel + " → " + to + (at ? " by " + DateTime.clockText(at) : "")
        }
        // a fixed temperature has no next period, so it stands alone
        return root.statusLabel + (at ? " until " + DateTime.clockText(at) : "")
    }

    function _parseCoord(s: string): bool {
        const m = /^([+-]\d{2})(\d{2})(\d{2})?([+-]\d{3})(\d{2})(\d{2})?$/.exec((s || "").trim())
        if (!m) return false
        const latDeg = Math.abs(Number(m[1]))
        const latMin = Number(m[2])
        const latSec = m[3] ? Number(m[3]) : 0
        const lonDeg = Math.abs(Number(m[4]))
        const lonMin = Number(m[5])
        const lonSec = m[6] ? Number(m[6]) : 0
        if (latMin >= 60 || lonMin >= 60 || latSec >= 60 || lonSec >= 60
                || latDeg > 90 || lonDeg > 180
                || (latDeg === 90 && (latMin > 0 || latSec > 0))
                || (lonDeg === 180 && (lonMin > 0 || lonSec > 0))) return false
        const latSign = m[1].charAt(0) === "-" ? -1 : 1
        const lonSign = m[4].charAt(0) === "-" ? -1 : 1
        root._autoLat = latSign * (latDeg + latMin / 60 + latSec / 3600)
        root._autoLon = lonSign * (lonDeg + lonMin / 60 + lonSec / 3600)
        root._geoResolved = true
        return true
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
            // the tables list only canonical zones; an alias like Asia/Calcutta would fall back to 45°N
            "for d in \"$TZDIR\" /etc/zoneinfo /usr/share/zoneinfo; do " +
            "  [ -n \"$d\" ] && [ -r \"$d/tzdata.zi\" ] || continue; " +
            "  for _ in 1 2 3; do " +
            "    l=\"$(awk -v z=\"$tz\" '$1==\"L\" && $3==z {print $2; exit}' \"$d/tzdata.zi\")\"; " +
            "    [ -n \"$l\" ] && [ \"$l\" != \"$tz\" ] || break; tz=\"$l\"; " +
            "  done; break; " +
            "done; " +
            // NixOS has no /usr/share/zoneinfo: its tables live in /etc/zoneinfo, and $TZDIR
            // names them wherever else a system keeps them; a miss everywhere falls back to 45°N
            "c=; for d in \"$TZDIR\" /etc/zoneinfo /usr/share/zoneinfo; do " +
            "  [ -n \"$d\" ] || continue; " +
            "  for f in \"$d/zone1970.tab\" \"$d/zone.tab\"; do " +
            "    [ -r \"$f\" ] || continue; " +
            "    c=\"$(awk -v z=\"$tz\" 'BEGIN{FS=\"\\t\"} $0 !~ /^#/ && $3==z {print $2; exit}' \"$f\")\"; " +
            "    [ -n \"$c\" ] && break; " +
            "  done; " +
            "  [ -n \"$c\" ] && { printf '%s\\n' \"$c\"; break; }; " +
            "done"]
        stdout: StdioCollector { id: _geoOut }
        onExited: code => {
            // a switch that came while this ran makes its answer the old zone's
            if (root._geoRerun) {
                root._geoRerun = false
                // a tick later, so the rerun arms a timeout of its own: BoundedProcess arms it on the running edge
                Qt.callLater(root._lookupLocation)
                return
            }
            const forSwitch = root._geoForSwitch
            root._geoForSwitch = false
            // a lookup that failed or found nothing lets the next menu open try again
            if (!_geoProc.completedSuccessfully(code) || !root._parseCoord(_geoOut.text)) {
                root._geoStarted = false
                return
            }
            if (!forSwitch) return
            // the tool can go missing while the lookup runs, and the location it found then has nowhere to go
            if (!root.available) {
                console.debug(root.log, "silere-shell: timezone switched while sunsetr is missing; location write dropped")
                return
            }
            console.info(root.log, "silere-shell: timezone switched; sunsetr gets the new zone's location")
            root._configLat = Number(root._autoLat.toFixed(2))
            root._configLon = Number(root._autoLon.toFixed(2))
            root._queueSet({ latitude: root._autoLat.toFixed(2), longitude: root._autoLon.toFixed(2) })
        }
    }

    Timer {
        interval: 60000; repeat: true
        running: root.available && root._watched && !Idle.isIdle
        onTriggered: root._solarTick++
    }
    Connections {
        target: Idle
        function onIsIdleChanged() { if (!Idle.isIdle) root._solarTick++ }
    }

    function toggle(): void {
        if (!available || _toggleProc.running) return
        const goingOn = !root.enabled
        console.info(root.log, "silere-shell: toggle requested:", goingOn ? "on" : "off")
        // a toggle from anywhere settles the one a waiting keybind asked for, so it must not toggle again;
        // a check already running read the unit before this toggle and speaks for no later request
        root._toggleQueued = false
        _checkProc._forToggle = false
        root._checkError = false
        root.lastError = ""
        // optimistic: the row flips the moment it's tapped, and _checkActive
        // (run from onExited below) reconciles it with the unit if the call failed
        root.enabled = goingOn
        _toggleProc.exec(["systemctl", "--user", goingOn ? "start" : "stop", root._unit])
    }

    // a check already in flight when a reconciliation is requested would otherwise
    // just drop it; queue it instead so a post-toggle recheck is never lost
    property bool _recheckPending: false

    // a check can time out while the user manager is slow, so its error is cleared by the next
    // check that answers; a toggle error is not, so the two cannot share a string test
    property bool _checkError: false
    // a keybind toggle waiting on a fresh check; it counts as busy, so later presses never stack
    property bool _toggleQueued: false
    onAvailableChanged: {
        if (root.available) {
            root._readConfig()
            return
        }
        console.warn(root.log, "silere-shell: sunsetr is no longer available")
        root._toggleQueued = false
        // a check still running read the unit for the dropped request, so it settles no later one
        _checkProc._forToggle = false
        // the writes would only fail without the tool, and the next read follows its return
        root._setQueue = ({})
        root._readPending = false
    }

    function _checkActive(): void {
        if (!root.available) return
        if (_checkProc.running) { root._recheckPending = true; return }
        _checkProc._forToggle = root._toggleQueued
        _checkProc.exec(["systemctl", "--user", "is-active", "--quiet", root._unit])
    }

    readonly property bool _watched: ControlSurfaces.anyOpen

    // only an open surface shows `enabled`, so with every surface shut a start or stop from
    // outside the shell leaves it stale; the keybind's toggle waits on one fresh check instead
    // of a poll. "" means it toggled now and `enabled` names the request, "queued" that the
    // toggle follows the check, and "busy" or "unavailable" that nothing was asked
    function toggleFresh(): string {
        if (!root.available) {
            console.info(root.log, "silere-shell: keybind toggle answered: unavailable")
            return "unavailable"
        }
        if (_toggleProc.running || root._toggleQueued) {
            console.info(root.log, "silere-shell: keybind toggle answered: busy")
            return "busy"
        }
        if (root._watched) {
            root.toggle()
            return ""
        }
        root._toggleQueued = true
        // a check already running when the keybind came cannot see a change made after it
        // started, so it is followed by another instead of counting
        root._checkActive()
        console.info(root.log, "silere-shell: keybind toggle answered: queued behind a fresh check")
        return "queued"
    }

    // a surface opening is what instantiates this singleton, so _startGeo's opening edge is already spent by first load
    Component.onCompleted: { _checkActive(); _readConfig(); _startGeo() }

    property bool _geoStarted: false
    // the arc is drawn on more than one surface, so any open one wants the fallback location
    readonly property bool _geoWanted: available && root._watched
    // a lookup asked for by a timezone switch hands its answer to sunsetr; one for a menu open
    // only draws the arc, so a city chosen with `sunsetr geo` survives an ordinary start
    property bool _geoForSwitch: false
    property bool _geoRerun: false
    function _startGeo(): void {
        if (_geoStarted || !_geoWanted) return
        root._lookupLocation()
    }
    function _lookupLocation(): void {
        root._geoStarted = true
        if (_geoProc.running) { root._geoRerun = true; return }
        _geoProc.running = true
    }

    Connections {
        target: ControlSurfaces
        function onOpened() {
            root._checkActive()
            root._readConfig()
            root._startGeo()
            // the sun has moved since the last surface closed
            root._solarTick++
        }
    }
    Connections {
        target: SystemTools
        function onReadyChanged() { root._checkActive(); root._startGeo() }
        // a tool refresh can flip systemctl's availability; redo the check on the scan's completion edge
        function onScanRevisionChanged() { root._checkActive(); root._startGeo() }
    }
    // the geo fix is now the wrong city and every `new Date()` read below needs
    // re-checking too; _geoStarted only blocks a repeat lookup, so clear it first
    Connections {
        target: TimeZoneWatch
        function onSwitched() {
            root._geoStarted = false
            if (root.available) {
                root._geoForSwitch = true
                root._lookupLocation()
            }
            root._solarTick++
        }
    }

    function _acceptCheckResult(timedOut: bool, code: int): void {
        const rerun = root._recheckPending
        root._recheckPending = false
        if (timedOut) {
            console.warn(root.log, "silere-shell: is-active check timed out")
            // a toggle error names what actually failed, so a slow check does not replace it
            if (root.lastError.length === 0 || root._checkError) {
                root._checkError = true
                root.lastError = "Could not check sunsetr.service"
            }
            // the keybind was already told it was switching, so the row's error says why nothing did
            if (_checkProc._forToggle) root._toggleQueued = false
        } else {
            if (root._checkError) {
                root._checkError = false
                root.lastError = ""
            }
            if (root.enabled !== (code === 0))
                console.info(root.log, "silere-shell: is-active check changed the state to",
                    code === 0 ? "on" : "off")
            root.enabled = (code === 0)
            // the check the keybind waited on has read the unit, so the toggle starts from what it found
            if (_checkProc._forToggle && root._toggleQueued) root.toggle()
        }
        // a tick later, so the rerun arms a timeout of its own: BoundedProcess arms it on the running edge
        if (rerun) Qt.callLater(root._checkActive)
    }

    BoundedProcess {
        id: _checkProc
        property bool _forToggle: false
        timeoutMs: 5000
        onExited: (code) => root._acceptCheckResult(_checkProc.timedOut, code)
    }

    BoundedProcess {
        id: _toggleProc
        timeoutMs: 5000
        stderr: StdioCollector { id: _toggleErr }
        onExited: (code) => {
            if (!_toggleProc.completedSuccessfully(code)) {
                console.warn(root.log, "silere-shell: unit command failed:",
                    _toggleProc.command.slice(0, 3).join(" "), "exit", code, "timed out:", _toggleProc.timedOut)
                root._checkError = false
                root.lastError = SafeText.lastNonEmptyLine(
                    _toggleErr.text, "sunsetr.service did not respond", 160)
            }
            root._checkActive()
        }
    }

    // catches drift from outside the shell (a manual systemctl call, the unit
    // failing on its own) since only systemd — not this singleton — decides
    // when the daemon actually starts or stops. Only an open control surface
    // shows `enabled`, and opening one checks at once, so this runs only while
    // one is open; the keybind reads afresh through toggleFresh() instead.
    readonly property bool _pollWanted: root._watched
    Timer {
        interval: 60000; repeat: true
        running: root.available && root._pollWanted && !Idle.isIdle
        onRunningChanged: console.debug(root.log, "silere-shell: drift poll", running ? "started" : "stopped")
        onTriggered: root._checkActive()
    }


    onEnabledChanged: if (!root.enabled) root._clearLive()

    function _clearLive(): void {
        root._live = false
        root._period = ""
        root._transitioning = false
        root._currentTemp = 0
        root._targetTemp = 0
        root._nextPeriodAt = null
    }

    // a quoted number and a bare one read the same; anything else is NaN, never the 0 Number("") gives
    function _num(v): real {
        if (typeof v === "number") return v
        if (typeof v !== "string" || v.trim().length === 0) return NaN
        return Number(v.trim())
    }
    function _kelvin(v): int {
        const n = root._num(v)
        return isFinite(n) ? Math.round(n) : 0
    }
    // sunsetr stamps nanoseconds, and the engine's date parser takes no more than milliseconds
    function _parseStamp(v): var {
        if (typeof v !== "string") return null
        const d = new Date(v.trim().replace(/(\.\d{3})\d+/, "$1"))
        return isNaN(d.getTime()) ? null : d
    }

    function _acceptStatusLine(line: string): void {
        const text = String(line || "").trim()
        // with no daemon the follow answers in plain text on stdout, which falls out here
        if (text.charAt(0) !== "{" || !root.enabled) return
        let ev
        try { ev = JSON.parse(text) } catch (e) { return }
        if (!ev || typeof ev !== "object") return
        switch (ev.event_type) {
        case "state_applied":
            root._applyState(ev)
            break
        case "period_changed":
            console.info(root.log, "silere-shell: period changed from", String(ev.from_period ?? ""),
                "to", String(ev.to_period ?? ""))
            break
        // a preset swaps the config `get` reads, so it is read again like an edit
        case "preset_changed":
        case "config_changed":
            root._readConfig()
            break
        }
    }

    function _applyState(ev): void {
        root._period = String(ev.period ?? "")
        root._transitioning = ev.state === "transitioning"
        root._currentTemp = root._kelvin(ev.current_temp)
        root._targetTemp = root._kelvin(ev.target_temp)
        root._nextPeriodAt = root._parseStamp(ev.next_period)
        if (!root._live) {
            console.info(root.log, "silere-shell: status stream connected")
            // the daemon writes its config on its first start, so one missing before may exist now
            if (!root._configKnown) root._readConfig()
        }
        root._live = true
        console.debug(root.log, "silere-shell: state applied:", root._period, root._currentTemp + "K")
    }

    // command stays a constant for the reason Caffeine's watcher gives: gating it on what
    // flips superviseWhen would race two bindings off one signal
    SupervisedProcess {
        id: _statusReader
        superviseWhen: root.available && root.enabled
        // systemd calls a simple unit active once it forks, before sunsetr listens, so the
        // follow can find no daemon at first; the retries start fast and stay close together
        restartDelay: 1000
        maxRestartDelay: 8000
        // the follow exits 0 both when no daemon answers yet and when the daemon stops, and
        // either clears; a missing binary fails to start, which SupervisedProcess gives up on itself
        giveUpCodes: []
        command: ["sunsetr", "status", "--json", "--follow"]
        stdout: SplitParser {
            onRead: line => root._acceptStatusLine(line)
        }
        onRunningChanged: {
            if (!running) return
            root._live = false
            console.debug(root.log, "silere-shell: status reader started, restart", _statusReader._restartCount)
        }
        onExited: (code, status) => {
            const lost = root._live
            if (lost) console.info(root.log, "silere-shell: status stream lost: exit", code)
            else console.debug(root.log, "silere-shell: status reader exited before any state: exit", code)
            root._live = false
            // a stream that was up ends when the daemon does, so the unit may have stopped. One that
            // never connected says nothing about the unit and would check on every restart; a toggle
            // in flight checks from its own exit, and a check now would read the unit before it
            if (lost && root.enabled && !_toggleProc.running) root._checkActive()
        }
    }


    // a read of the file before a write lands would undo the write's optimistic value, so a
    // read asked for while one is outstanding waits for them to drain
    property bool _readPending: false
    // fields waiting for the running `set`, by name: a slider sweep's last value replaces the rest
    property var _setQueue: ({})
    // counts the writes started, so a read that began before the latest one is known to be stale
    // even when that write has already finished
    property int _setGeneration: 0

    function _hasQueuedSets(): bool {
        return Object.keys(root._setQueue).length > 0
    }

    function _readConfig(): void {
        if (!root.available) return
        if (_getProc.running || _setProc.running || root._hasQueuedSets()) {
            root._readPending = true
            return
        }
        root._readPending = false
        _getProc._setGeneration = root._setGeneration
        // named fields fail the whole read when one is absent, as a clock or static config's
        // coordinates are; `all` prints only what the file holds
        _getProc.exec(["sunsetr", "get", "all", "--json"])
    }

    function _drainConfig(): void {
        if (root._hasQueuedSets()) root._runSets()
        else if (root._readPending) root._readConfig()
    }

    // `HH:MM:SS` to minutes of the day; -1 when it is not one
    function _clockMinutes(v): int {
        const m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(typeof v === "string" ? v.trim() : "")
        if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) return -1
        return Number(m[1]) * 60 + Number(m[2])
    }
    function _clockText(min: int): string {
        const m = ((Math.round(min) % 1440) + 1440) % 1440
        const pad = n => (n < 10 ? "0" : "") + n
        return pad(Math.floor(m / 60)) + ":" + pad(m % 60) + ":00"
    }

    // every value `get --json` prints is a string, numbers included. Only the mode is required:
    // the file holds just the fields its mode uses, and an absent one keeps its last value
    function _acceptConfig(text: string): bool {
        let j
        try { j = JSON.parse(String(text || "").trim()) } catch (e) { return false }
        if (!j || typeof j !== "object" || Array.isArray(j)) return false
        const mode = String(j.transition_mode ?? "")
        if (root._modes.indexOf(mode) < 0) return false
        root._mode = mode
        const temp = root._num(j.night_temp)
        if (temp > 0) root._nightTemp = Math.round(temp)
        const sunset = root._clockMinutes(j.sunset)
        const sunrise = root._clockMinutes(j.sunrise)
        if (sunset >= 0) root._clockSunsetMin = sunset
        if (sunrise >= 0) root._clockSunriseMin = sunrise
        const lat = root._num(j.latitude)
        const lon = root._num(j.longitude)
        if (Math.abs(lat) <= 90) root._configLat = lat
        if (Math.abs(lon) <= 180) root._configLon = lon
        root._configKnown = true
        return true
    }

    BoundedProcess {
        id: _getProc
        property int _setGeneration: 0
        timeoutMs: 5000
        stdout: StdioCollector { id: _getOut }
        onExited: (code) => {
            if (_setProc.running || root._hasQueuedSets()
                    || _getProc._setGeneration !== root._setGeneration) {
                // read before a write landed; the read after the writes drain replaces it
                root._readPending = true
            } else if (!_getProc.completedSuccessfully(code)) {
                console.warn(root.log, "silere-shell: config read failed: exit", code,
                    "timed out:", _getProc.timedOut)
                root._configKnown = false
            } else if (!root._acceptConfig(_getOut.text)) {
                console.warn(root.log, "silere-shell: config read gave no transition mode")
                root._configKnown = false
            }
            // a tick later, so the next run arms a timeout of its own: BoundedProcess arms it on the running edge
            if (root._readPending || root._hasQueuedSets()) Qt.callLater(root._drainConfig)
        }
    }

    function _queueSet(fields: var): void {
        // a lookup can finish after the tool went missing, and a field left queued would hold
        // every later read back
        if (!root.available) {
            console.debug(root.log, "silere-shell: config write dropped, sunsetr is missing:", Object.keys(fields).join(" "))
            return
        }
        root._setQueue = Object.assign({}, root._setQueue, fields)
        root._runSets()
    }

    function _runSets(): void {
        if (!root.available || _setProc.running || !root._hasQueuedSets()) return
        const fields = root._setQueue
        root._setQueue = ({})
        const args = Object.keys(fields).map(k => k + "=" + fields[k])
        // a location is the one value here that says where the machine is, so the journal names its field only
        const shown = Object.keys(fields).map(k => k === "latitude" || k === "longitude" ? k : k + "=" + fields[k])
        console.info(root.log, "silere-shell: config write:", shown.join(" "))
        root._setGeneration++
        _setProc.exec(["sunsetr", "set"].concat(args))
    }

    BoundedProcess {
        id: _setProc
        timeoutMs: 5000
        onExited: (code) => {
            if (!_setProc.completedSuccessfully(code))
                console.warn(root.log, "silere-shell: config write failed: exit", code,
                    "timed out:", _setProc.timedOut)
            // read back after every write: a failed one restores the real values, a good one confirms them
            root._readPending = true
            // a tick later, so the next run arms a timeout of its own: BoundedProcess arms it on the running edge
            Qt.callLater(root._drainConfig)
        }
    }

    function setNightTemp(k: int): void {
        if (!root.available) return
        const t = Math.max(1000, Math.min(20000, Math.round(k)))
        root._nightTemp = t
        root._queueSet({ night_temp: String(t) })
    }

    // "sun" follows the sun; "clock" keeps whichever clock mode the config already names, and
    // from "fixed" starts the default one
    function setSchedule(s: string): void {
        if (!root.available) return
        if (s === "sun") {
            root._mode = "geo"
            root._queueSet({ transition_mode: "geo" })
        } else if (s === "clock" && root._clockModes.indexOf(root._mode) < 0) {
            root._mode = "start_at"
            root._queueSet({ transition_mode: "start_at" })
        }
    }

    function setClockSunset(min: int): void {
        if (!root.available) return
        root._clockSunsetMin = ((Math.round(min) % 1440) + 1440) % 1440
        root._queueSet({ sunset: root._clockText(min) })
    }

    function setClockSunrise(min: int): void {
        if (!root.available) return
        root._clockSunriseMin = ((Math.round(min) % 1440) + 1440) % 1440
        root._queueSet({ sunrise: root._clockText(min) })
    }
}
