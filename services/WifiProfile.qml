pragma Singleton

// Backs the connected Wi-Fi entry's details panel: the profile's saved band
// setting, IPv4 configuration, and the frequency the radio actually landed
// on. Quickshell.Networking's WifiNetwork exposes signal and security but not
// frequency or profile identity, so this reaches nmcli for the rest — kept
// out of Network.qml since none of it is needed until a network is expanded.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property bool toolAvailable: SystemTools.hasNmcli

    // pushed by the details view while its disclosure is open; nothing here
    // polls unless someone is actually looking at it
    property bool active: false
    function setActive(next: bool): void {
        // on_WantedChanged below fires the actual refresh once this flip lands
        root.active = next
    }

    readonly property bool _wanted: root.active && root.toolAvailable
        && Network.connected && Network.isWifi && !Idle.isIdle

    property int _frequencyMHz: 0
    readonly property string band: {
        const f = root._frequencyMHz
        if (f <= 0) return ""
        if (f < 3000) return "2.4 GHz"
        if (f < 5925) return "5 GHz"
        return "6 GHz"
    }
    readonly property string bandFrequencyLabel: root.band.length > 0
        ? root.band + " · " + root._frequencyMHz + " MHz" : ""
    property string securityLabel: ""

    property string profileUuid: ""
    property string ipv4Address: ""
    property string gateway: ""
    property list<string> _dnsServers: []
    readonly property string dnsLabel: root._dnsServers.join(", ")

    // the profile's stored 802-11-wireless.band ("" auto / "bg" / "a"); optimistic
    // while a write is in flight, reconciled from nmcli once it lands
    property string savedBand: ""
    property string _optimisticBand: ""
    // the uuid a write is actually in flight against — read back at each step of the
    // modify-then-activate chain instead of profileUuid, which can move on to a
    // different network mid-chain if the radio reconnects elsewhere underneath it
    property string _pendingUuid: ""
    property bool bandPending: false
    readonly property string bandSetting: root.bandPending ? root._optimisticBand : root.savedBand
    property string lastError: ""

    function setBand(value: string): void {
        if (!root.toolAvailable || root.profileUuid.length === 0) return
        if (value === root.bandSetting) return
        if (_modifyProc.running || _activateProc.running) return
        root.lastError = ""
        root._optimisticBand = value
        root._pendingUuid = root.profileUuid
        root.bandPending = true
        _modifyProc.exec(["nmcli", "connection", "modify", root._pendingUuid, "wifi.band", value])
    }

    // colon-delimited nmcli terse output escapes both the field separator and
    // its own escape character with a leading backslash
    function _splitLine(line: string): var {
        const fields = []
        let cur = ""
        let escaped = false
        for (let i = 0; i < line.length; i++) {
            const ch = line[i]
            if (escaped) { cur += ch; escaped = false }
            else if (ch === "\\") { escaped = true }
            else if (ch === ":") { fields.push(cur); cur = "" }
            else { cur += ch }
        }
        if (escaped) cur += "\\"
        fields.push(cur)
        return fields
    }

    // a tick that lands mid-request just waits for the next one rather than queuing —
    // these are cheap, frequent reads, not a one-shot action worth requeuing
    function _refreshNow(): void {
        if (!root._wanted) return
        if (!_freqProc.running)
            _freqProc.exec(["nmcli", "-t", "-f", "ACTIVE,FREQ,SECURITY", "dev", "wifi", "list"])
        if (!_deviceProc.running && Network.deviceName.length > 0)
            root._queryDevice()
    }

    // shared by the periodic refresh above and launchEditor()'s on-demand freshness
    // check below, so the argv only lives in one place
    function _queryDevice(): void {
        _deviceProc.exec(["nmcli", "-t", "-f",
            "GENERAL.CON-UUID,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS",
            "device", "show", Network.deviceName])
    }

    on_WantedChanged: if (root._wanted) root._refreshNow()

    Timer {
        interval: 6000
        repeat: true
        running: root._wanted
        onTriggered: root._refreshNow()
    }

    BoundedProcess {
        id: _freqProc
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        property int _candidateFreq: 0
        property string _candidateSecurity: ""
        property bool _candidateFound: false
        onRunningChanged: if (running) {
            _candidateFreq = 0
            _candidateSecurity = ""
            _candidateFound = false
        }
        stdout: SplitParser {
            onRead: line => {
                if (_freqProc._candidateFound) return
                const fields = root._splitLine(line)
                if (fields.length < 3 || fields[0] !== "yes") return
                const m = /^(\d+)/.exec(fields[1].trim())
                if (!m) return
                _freqProc._candidateFreq = Number(m[1])
                _freqProc._candidateSecurity = SafeText.singleLineText(fields.slice(2).join(":"), 64)
                _freqProc._candidateFound = true
            }
        }
        // hold the last known reading through a transient scan failure rather than blanking it
        onExited: (code) => {
            if (code !== 0 || !_freqProc._candidateFound) return
            root._frequencyMHz = _freqProc._candidateFreq
            root.securityLabel = _freqProc._candidateSecurity === "--"
                || _freqProc._candidateSecurity.length === 0
                ? "Open" : _freqProc._candidateSecurity
        }
    }

    BoundedProcess {
        id: _deviceProc
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        property string _uuid: ""
        property string _addr: ""
        property string _gw: ""
        property list<string> _dns: []
        onRunningChanged: if (running) {
            _uuid = ""; _addr = ""; _gw = ""; _dns = []
        }
        stdout: SplitParser {
            onRead: line => {
                const fields = root._splitLine(line)
                if (fields.length < 2) return
                const key = fields[0]
                const value = fields.slice(1).join(":")
                if (key === "GENERAL.CON-UUID") _deviceProc._uuid = value
                else if (key.indexOf("IP4.ADDRESS") === 0 && _deviceProc._addr.length === 0)
                    _deviceProc._addr = value
                else if (key === "IP4.GATEWAY") _deviceProc._gw = value
                else if (key.indexOf("IP4.DNS") === 0 && value.length > 0)
                    _deviceProc._dns.push(value)
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                // launchEditor() forced this read outside the usual _wanted gate to get a
                // fresh uuid; a failed lookup must surface rather than leave the click inert
                if (root._launchPending) {
                    root._launchPending = false
                    root.lastError = "could not confirm the active connection"
                }
                return
            }
            root.profileUuid = root._uuidPattern.test(_deviceProc._uuid) ? _deviceProc._uuid : ""
            root.ipv4Address = SafeText.singleLineText(_deviceProc._addr, 64)
            root.gateway = SafeText.singleLineText(_deviceProc._gw, 64)
            root._dnsServers = _deviceProc._dns.map(d => SafeText.singleLineText(d, 64))
            // a slow band read from a prior tick must not be reset mid-flight by this one
            if (root.profileUuid.length > 0 && !_bandProc.running)
                _bandProc.exec(["nmcli", "-t", "-f", "802-11-wireless.band",
                    "connection", "show", root.profileUuid])

            if (root._launchPending) {
                root._launchPending = false
                if (root.profileUuid.length > 0) {
                    if (!_editorLauncher.launch("uuid", root.profileUuid, root._uuidPattern))
                        root.lastError = _editorLauncher.lastError.length > 0
                            ? _editorLauncher.lastError : "could not open the editor"
                } else {
                    root.lastError = "could not confirm the active connection"
                }
            }
        }
    }

    BoundedProcess {
        id: _bandProc
        timeoutMs: 8000
        environment: ({ "LC_ALL": "C" })
        property string _value: ""
        property bool _found: false
        onRunningChanged: if (running) { _value = ""; _found = false }
        stdout: SplitParser {
            onRead: line => {
                if (_bandProc._found) return
                const fields = root._splitLine(line)
                if (fields.length < 1 || fields[0] !== "802-11-wireless.band") return
                _bandProc._value = fields.slice(1).join(":").trim()
                _bandProc._found = true
            }
        }
        onExited: (code) => {
            if (code === 0 && _bandProc._found) root.savedBand = _bandProc._value
        }
    }

    BoundedProcess {
        id: _modifyProc
        timeoutMs: 10000
        environment: ({ "LC_ALL": "C" })
        stderr: StdioCollector { id: _modifyErr }
        onExited: (code) => {
            if (_modifyProc.timedOut || code !== 0) {
                root.lastError = _modifyErr.text.trim().split("\n").pop() || "could not change the Wi-Fi band"
                root.bandPending = false
                return
            }
            _activateProc.exec(["nmcli", "connection", "up", root._pendingUuid])
        }
    }

    BoundedProcess {
        id: _activateProc
        timeoutMs: 20000
        environment: ({ "LC_ALL": "C" })
        stderr: StdioCollector { id: _activateErr }
        onExited: (code) => {
            if (_activateProc.timedOut || code !== 0) {
                root.lastError = _activateErr.text.trim().split("\n").pop() || "could not reconnect with the new band"
            } else if (root.profileUuid === root._pendingUuid) {
                // still the same network we wrote to; a switch mid-chain leaves this
                // false, so the new network's own reconciled read wins instead
                root.savedBand = root._optimisticBand
            }
            root.bandPending = false
            root._refreshNow()
        }
    }

    // "Edit connection…" launches a user-declared command template (ShellSettings.wifiEditCommand)
    // through the shared launcher; {uuid} is substituted with the active profile's uuid when
    // present in the template. Whitespace splitting, the PATH probe, the launch cooldown and the
    // detached exec all live in TemplateLauncher — shared with the Bluetooth manager escape hatch.
    TemplateLauncher {
        id: _editorLauncher
        template: ShellSettings.wifiEditCommand
    }
    readonly property bool editorAvailable: _editorLauncher.available
    readonly property var _uuidPattern: /^[0-9a-fA-F-]+$/
    // a query kicked off by launchEditor() below is still "pending" until _deviceProc.onExited
    // above resolves it (launch or surface an error) — a second click while it is in flight
    // rides the same completion instead of starting a duplicate lookup
    property bool _launchPending: false

    function launchEditor(): void {
        if (!root.editorAvailable || _editorLauncher.onCooldown) return
        root.lastError = ""
        // no {uuid} in the template: nothing to look up, launch immediately
        if (!_editorLauncher.usesPlaceholder("uuid")) { _editorLauncher.launch(); return }
        // profileUuid only refreshes on a timer while the details disclosure is open
        // (root._wanted), so a bar-pill click can otherwise substitute a stale uuid or
        // silently no-op on an empty one; force a fresh read here regardless of that
        // gate and launch once it lands rather than trusting whatever profileUuid holds
        if (!root.toolAvailable || Network.deviceName.length === 0) {
            root.lastError = "no active connection to edit"
            return
        }
        root._launchPending = true
        if (!_deviceProc.running) root._queryDevice()
    }
}
