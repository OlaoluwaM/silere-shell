pragma Singleton

// Backend split: powerprofilesctl (power-profiles-daemon) is the upstream-standard
// control surface and wins whenever it resolves on PATH. This site runs asusd
// instead of power-profiles-daemon, so asusctl's own `profile` subcommand is the
// live path here — tried only as a fallback, same "prefer the standard tool first"
// order SystemTools already uses for its other optional-tool probes. The two
// backends report/accept differently-shaped profile names (lowercase-hyphenated
// for powerprofilesctl, Capitalized for asusctl); `profile`/`profiles`/`current`
// are kept exactly as the active backend reports them, and only `label` normalizes.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool hasPowerProfilesCtl: SystemTools.hasPowerProfilesCtl
    readonly property bool hasAsusctl: SystemTools.hasAsusctl
    readonly property string backend: root.hasPowerProfilesCtl ? "powerprofilesctl"
        : root.hasAsusctl ? "asusctl" : ""
    readonly property bool available: root.backend.length > 0

    readonly property bool syncing: _get.running || _set.running || _getRetry.running
    property string profile: ""
    // same value as `profile`, under the name the settings-page contract wants;
    // `profile` stays because HomePage/QuickActionsPopup/PowerRailContent already
    // read it and there is no reason to touch three already-working call sites
    readonly property string current: root.profile
    property var profiles: []
    property string lastError: ""

    // the daemon reports an active profile it is not actually delivering (lap mode,
    // thermals); the reason string is empty whenever it is delivering, so absence
    // fails closed to "fine". asusd exposes no equivalent signal, so this only ever
    // arms on the powerprofilesctl backend.
    property string _degradedReason: ""
    readonly property bool degraded: root.profile === "performance" && root._degradedReason.length > 0

    function _titleCase(s: string): string {
        return String(s || "").split(/[\s_-]+/).filter(w => w.length > 0)
            .map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ")
    }
    readonly property string label: root._titleCase(root.profile)
    readonly property string glyph: {
        const p = root.profile.toLowerCase()
        if (p.indexOf("performance") >= 0) return "󰓅"
        if (p.indexOf("saver") >= 0 || p.indexOf("quiet") >= 0) return "󰾆"
        return "󰾅"
    }

    property int _writeGen: 0
    property bool _correctiveRefreshPending: false
    // a read error is cleared by the next good read; a set error is not, so the two cannot share a string test
    property bool _readError: false

    property int _getRetries: 0
    readonly property int _getRetryMax: 4
    Timer {
        id: _getRetry
        interval: 600
        onTriggered: {
            if (_get.running || _set.running) {
                restart()
                return
            }
            root.refresh()
        }
    }

    function _getCommand(): var {
        return root.backend === "asusctl" ? ["asusctl", "profile", "get"] : ["powerprofilesctl", "get"]
    }
    function _setCommand(name: string): var {
        return root.backend === "asusctl" ? ["asusctl", "profile", "set", name] : ["powerprofilesctl", "set", name]
    }
    function _listCommand(): var {
        return root.backend === "asusctl" ? ["asusctl", "profile", "list"] : ["powerprofilesctl", "list"]
    }

    function refresh(): void {
        if (!available || _get.running || _set.running) return
        _get._corrective = root._correctiveRefreshPending
        _correctiveRefreshPending = false
        _get._gen = root._writeGen
        _get.exec(root._getCommand())
    }

    function _refreshDegraded(): void {
        if (root.backend !== "powerprofilesctl" || root.profile !== "performance") {
            if (_degradedProc.running) _degradedProc.running = false
            root._degradedReason = ""
            return
        }
        if (!SystemTools.hasBusctl) {
            root._degradedReason = ""
            return
        }
        if (_degradedProc.running) return
        // the daemon owns both names; the newer one first, the pre-0.20 name as fallback
        _degradedProc.exec(["bash", "-c",
            "busctl get-property org.freedesktop.UPower.PowerProfiles" +
            " /org/freedesktop/UPower/PowerProfiles" +
            " org.freedesktop.UPower.PowerProfiles PerformanceDegraded 2>/dev/null" +
            " || busctl get-property net.hadess.PowerProfiles" +
            " /net/hadess/PowerProfiles" +
            " net.hadess.PowerProfiles PerformanceDegraded 2>/dev/null"])
    }

    function _queueCorrectiveRefresh(): void {
        root._correctiveRefreshPending = true
        root._getRetries = 0
        _getRetry.restart()
    }

    // powerprofilesctl's bare `get` output; validated against the profile list this
    // backend itself reported, or — before that list has loaded — a plain
    // single-token shape, so a multi-word/garbage read is rejected either way
    function _parseProfile(value): string {
        const p = SafeText.singleLineText(value, 64)
        if (root.profiles.length > 0) return root.profiles.indexOf(p) >= 0 ? p : ""
        return /^[A-Za-z0-9_-]+$/.test(p) ? p : ""
    }

    // asusctl's `profile get` prints a small report, not a bare name:
    //   Active profile: Performance
    //
    //   AC profile Performance
    //   Battery profile Balanced
    // the active profile is the trailing word(s) on the "Active profile:" line
    function _parseAsusCurrent(value): string {
        const m = /^Active profile:\s*(.+)$/m.exec(String(value || ""))
        return m ? SafeText.singleLineText(m[1], 64) : ""
    }

    function _parseCurrent(value): string {
        return root.backend === "asusctl" ? root._parseAsusCurrent(value) : root._parseProfile(value)
    }

    // busctl prints a typed property as: s "reason"
    function _parseDegraded(value): string {
        const line = SafeText.singleLineText(value, 160)
        const m = /^s\s+"(.*)"$/.exec(line)
        return m ? SafeText.singleLineText(m[1], 64) : ""
    }

    // powerprofilesctl lists each profile as its own "name:" header line (the active
    // one prefixed with "* "); asusctl just prints one bare name per line, e.g.
    //   Quiet
    //   Balanced
    //   Performance
    function _parsePpdList(text): var {
        const out = []
        const lines = String(text || "").split(/\r?\n/)
        for (let i = 0; i < lines.length; i++) {
            const m = /^\*?\s*([A-Za-z0-9_-]+):\s*$/.exec(lines[i])
            if (m) out.push(m[1])
        }
        return out
    }
    function _parseAsusList(text): var {
        const out = []
        const lines = String(text || "").split(/\r?\n/)
        for (let i = 0; i < lines.length; i++) {
            const t = SafeText.singleLineText(lines[i], 32)
            if (t.length > 0 && /^[A-Za-z][A-Za-z0-9 _-]*$/.test(t)) out.push(t)
        }
        return out
    }

    function _listProfiles(): void {
        if (!root.available || _list.running) return
        _list.exec(root._listCommand())
    }

    // shared by cycle() and setProfile(): optimistic, same spirit as Caffeine's
    // toggle() — the row/pill/chip flips the moment it's tapped, and refresh() (queued
    // through the corrective retry chain below) reconciles it once the tool actually
    // answers, so a slow or failing set reads as briefly-wrong rather than stuck
    function _applySet(name: string): void {
        root.profile = name
        root._readError = false
        root.lastError = ""
        root._writeGen++
        _set.exec(root._setCommand(name))
    }

    function cycle(): void {
        // _set.running guard: exec while a set's in flight drops the write but still flips the optimistic profile — UI and daemon diverge
        if (!available || profile === "" || _set.running || root.profiles.length === 0) return
        const idx = root.profiles.indexOf(root.profile)
        if (idx < 0) return
        root._applySet(root.profiles[(idx + 1) % root.profiles.length])
    }

    // direct pick from the settings-page chip row, as opposed to cycle()'s
    // next-in-list step from the home row / quick actions pill
    function setProfile(name: string): void {
        if (!available || _set.running || name === root.profile) return
        if (root.profiles.length > 0 && root.profiles.indexOf(name) < 0) return
        root._applySet(name)
    }

    Component.onCompleted: { if (root.available) root._listProfiles() }
    onBackendChanged: { root.profiles = []; if (root.available) root._listProfiles() }

    readonly property bool _watched: ControlSurfaces.anyOpen
    on_WatchedChanged: {
        if (root._watched) root._surfaceOpened()
        else if (!root._correctiveRefreshPending) _getRetry.stop()
    }

    function _surfaceOpened(): void {
        root._getRetries = 0
        root.refresh()
    }

    function _syncToolAvailability(): void {
        if (!SystemTools.ready) return
        if (root.available) {
            // cycle()/setProfile() step through this list, so a late tool arrival must fill it
            if (root.profiles.length === 0) root._listProfiles()
            if (root._watched) root.refresh()
            return
        }

        _getRetry.stop()
        if (_get.running) _get.running = false
        if (_set.running) _set.running = false
        if (_degradedProc.running) _degradedProc.running = false
        root._getRetries = 0
        root._correctiveRefreshPending = false
        root._readError = false
        root.profile = ""
        root._degradedReason = ""
        root.lastError = ""
    }

    Connections {
        target: SystemTools
        function onReadyChanged() { root._syncToolAvailability() }
        function onScanRevisionChanged() { root._syncToolAvailability() }
    }
    BoundedProcess {
        id: _get
        property int _gen: 0
        property bool _corrective: false
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _getOut }
        onTimeoutReached: {
            root._readError = true
            root.lastError = "Power mode check timed out"
        }
        onExited: (code) => {
            if (!root.available) return
            if (_set.running || _gen !== root._writeGen) return
            if (code === 0) {
                const p = root._parseCurrent(_getOut.text)
                if (p.length > 0) {
                    root.profile = p
                    root._refreshDegraded()
                    root._getRetries = 0
                    root._correctiveRefreshPending = false
                    if (root._readError) {
                        root._readError = false
                        root.lastError = ""
                    }
                    return
                }
            }
            const shouldRetry = root.profile === "" || _corrective
            if (shouldRetry && root.available && (root._watched || _corrective)
                    && root._getRetries < root._getRetryMax) {
                root._getRetries++
                root._correctiveRefreshPending = _corrective
                _getRetry.restart()
                return
            }
            if (shouldRetry && !timedOut) {
                root._readError = true
                root.lastError = "Could not verify the power mode"
            }
        }
    }
    BoundedProcess {
        id: _list
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _listOut }
        onExited: (code) => {
            if (timedOut || code !== 0) return
            const parsed = root.backend === "asusctl"
                ? root._parseAsusList(_listOut.text) : root._parsePpdList(_listOut.text)
            if (parsed.length > 0) root.profiles = parsed
        }
    }
    BoundedProcess {
        id: _degradedProc
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _degradedOut }
        onTimeoutReached: root._degradedReason = ""
        onExited: (code) => {
            if (!root.available) {
                root._degradedReason = ""
                return
            }
            root._degradedReason = (root.backend === "powerprofilesctl"
                    && root.profile === "performance" && code === 0 && !timedOut)
                ? root._parseDegraded(_degradedOut.text) : ""
        }
    }
    BoundedProcess {
        id: _set
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        stderr: StdioCollector { id: _setErr }
        onTimeoutReached: {
            root._readError = false
            root.lastError = "Power mode change timed out"
        }
        onExited: (code) => {
            if (!root.available) return
            if (timedOut) {
                root._queueCorrectiveRefresh()
                return
            }
            if (code === 0) {
                root._readError = false
                root.lastError = ""
                root._queueCorrectiveRefresh()
                return
            }
            // the row re-reads the daemon, so a swallowed failure just flips the label back with no reason given
            root._readError = false
            root.lastError = SafeText.boundedText(
                _setErr.text.trim().split("\n").pop() || "Could not change the power mode", 160)
            root._queueCorrectiveRefresh()
        }
    }

    // catches drift the menu-open refresh above cannot: an asusd hotkey cycling the
    // profile, or a manual powerprofilesctl/asusctl call, while the menu stays open.
    // The System page is the drift-sensitive consumer (a static picker is wrong the
    // instant something else changes the profile underneath it); Home and the quick
    // actions pill already reconcile on their own open/close and just share this poll.
    // Paused the same way Caffeine/NightLight pause theirs: idle, and — since nothing
    // reads `profile` while the menu itself is shut — menu-closed too.
    Timer {
        interval: 45000; repeat: true
        running: root.available && MenuState.open && !Idle.isIdle
        onTriggered: root.refresh()
    }
}
