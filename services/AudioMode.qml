pragma Singleton

// Over classic Bluetooth a headset plays either high-quality audio with no mic or
// call-quality audio with one, never both. The deploying config turns off WirePlumber's
// autoswitch (a stand-in mic that flips the headset into call audio whenever an app
// records), so the choice is made here, the way GNOME's per-device profile picker makes
// it. Quickshell exposes no device profiles: the list comes from pw-dump and the switch
// goes through wpctl. Audio holds the shared presentation and user input while the
// default routes away and back onto the rebuilt headset node.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var _sinkProps: Audio.sinkReady && Audio.sink ? Audio.sink.properties : null
    readonly property string _deviceId: {
        const p = root._sinkProps
        if (!p || p["device.api"] !== "bluez5") return ""
        const id = String(p["device.id"] ?? "")
        // it lands in argv, so only a plain object id gets through
        return /^[0-9]+$/.test(id) ? id : ""
    }
    readonly property string current: root.kindOf(root._sinkProps
        ? String(root._sinkProps["api.bluez5.profile"] ?? "") : "")

    property string _listedDevice: ""
    property string _switchDevice: ""
    property string _switchSerial: ""
    property bool _sawFallback: false
    property bool _setSucceeded: false
    property int _listeningIndex: -1
    property int _callsIndex: -1

    // a device that offers only one kind (a speaker, a mono headset) has nothing to choose
    readonly property bool available: SystemTools.hasWpctl && root._deviceId.length > 0
        && root._listedDevice === root._deviceId
        && root._listeningIndex >= 0 && root._callsIndex >= 0

    property string _pending: ""
    readonly property bool switching: root._pending.length > 0
    readonly property string mode: root.switching ? root._pending : root.current

    function _atTarget(): bool {
        const serial = Audio.nodeSerial(Audio.sink)
        return Audio.sinkReady && root._deviceId === root._switchDevice
            && root.current === root._pending && serial !== "" && serial !== root._switchSerial
    }

    function _observeSwitch(): void {
        if (!root.switching) return
        const device = root._sinkProps ? String(root._sinkProps["device.id"] ?? "") : ""
        if (device !== "" && device !== root._switchDevice) root._sawFallback = true
        // Quickshell can resolve the replacement against the retained default name before
        // WirePlumber routes away. A new serial alone would release the hold too early.
        if (root._setSucceeded && root._sawFallback)
            Qt.callLater(root._completeSwitch)
    }

    function _completeSwitch(): void {
        // Recheck after Audio's bindings catch up; a queued completion can outlive its node.
        if (root.switching && root._setSucceeded && root._sawFallback && root._atTarget())
            root._finishSwitch(true)
    }

    // codec-suffixed names (a2dp-sink-aac, headset-head-unit-cvsd) share their family's
    // prefix; a duplex profile carries a mic, so it counts as calls. Untested against a
    // duplex headset: if its sink node reports a per-direction name (a2dp-sink, bap-sink)
    // instead of the device profile, `current` reads it as listening, a switch to calls only
    // ends on the settle backstop with the Listening chip lit, and setMode then refuses to
    // switch back, since the headset already reads as listening.
    function kindOf(profile: string): string {
        if (/^(a2dp|bap)-sink/.test(profile)) return "listening"
        if (/^headset-head-unit/.test(profile) || /-duplex/.test(profile)) return "calls"
        return ""
    }

    // PipeWire ranks each device's profiles, so the best-ranked of each kind stands for it
    function bestProfiles(dump, deviceId: string): var {
        const best = { listening: null, calls: null }
        const dev = Array.isArray(dump) ? dump.find(o => o && String(o.id) === deviceId
            && o.type === "PipeWire:Interface:Device") : null
        const list = dev && dev.info && dev.info.params ? dev.info.params.EnumProfile : null
        if (Array.isArray(list)) {
            for (const p of list) {
                if (!p || p.available === "no") continue
                const kind = root.kindOf(String(p.name ?? ""))
                const index = p.index
                const priority = Number(p.priority) || 0
                if (kind === "" || !Number.isInteger(index) || index < 0) continue
                if (!best[kind] || priority > best[kind].priority) best[kind] = { index, priority }
            }
        }
        return {
            listening: best.listening ? best.listening.index : -1,
            calls: best.calls ? best.calls.index : -1
        }
    }

    // the list stays cached through a switch's bounce; a fresh read on reconnect and on each
    // open of the Sound page catches a call profile that came up after the first read. Mid
    // switch only the switching headset is read: the default may bounce to another device
    function _listProfiles(fresh: bool): void {
        const id = root._deviceId
        if (id === "" || (!fresh && id === root._listedDevice) || !SystemTools.hasPwDump
                || _dump.running || (root.switching && id !== root._switchDevice)) return
        _dump._device = id
        _dump.exec(["pw-dump", id])
    }

    function setMode(kind: string): void {
        // a run still being stopped would clear the new request when it exits
        if (!root.available || root.switching || _set.running || kind === root.current) return
        const index = kind === "listening" ? root._listeningIndex
            : kind === "calls" ? root._callsIndex : -1
        if (index < 0) return
        root._switchDevice = root._deviceId
        root._switchSerial = Audio.nodeSerial(Audio.sink)
        root._sawFallback = false
        root._setSucceeded = false
        Audio.beginProfileSwitch()
        root._pending = kind
        _settle.restart()
        _set.exec(["wpctl", "set-profile", root._deviceId, String(index)])
    }

    function _finishSwitch(apply: bool): void {
        _settle.stop()
        Audio.endProfileSwitch(apply)
        root._pending = ""
        // a switch that ended on another device, or on none, leaves nothing to keep
        if (root._deviceId !== root._listedDevice) {
            root._listedDevice = ""
            root._listProfiles(false)
        }
    }

    // PipeWire reuses object ids, so a device change outside a switch takes the list along
    on_DeviceIdChanged: {
        if (!root.switching) root._listedDevice = ""
        root._listProfiles(false)
    }
    on_SinkPropsChanged: root._observeSwitch()
    Component.onCompleted: root._listProfiles(false)

    Connections {
        target: SystemTools
        function onScanRevisionChanged() { root._listProfiles(false) }
    }
    Connections {
        target: MenuState
        function onSoundSectionActiveChanged() {
            if (MenuState.soundSectionActive) root._listProfiles(true)
        }
    }

    // No fallback may be observed, or routing may choose another device permanently.
    // The deadline releases the UI; edits land only if the requested sink is now ready.
    Timer {
        id: _settle
        interval: 2000
        onTriggered: root._finishSwitch(root._setSucceeded && root._atTarget())
    }

    BoundedProcess {
        id: _dump
        property string _device: ""
        timeoutMs: 5000
        environment: ({ "LC_ALL": "C" })
        stdout: StdioCollector { id: _dumpOut }
        onExited: (code) => {
            // a read that outlived its device (outside a switch's bounce) is not published
            if (_dump.completedSuccessfully(code)
                    && (_dump._device === root._deviceId
                        || (root.switching && _dump._device === root._switchDevice))) {
                let parsed = null
                try { parsed = JSON.parse(_dumpOut.text) } catch (e) { parsed = null }
                const best = root.bestProfiles(parsed, _dump._device)
                root._listeningIndex = best.listening
                root._callsIndex = best.calls
                root._listedDevice = _dump._device
            }
            // A failed read is not retried until the device changes, so it cannot spin. The
            // next read starts a tick later so it arms a timeout of its own: BoundedProcess arms
            // it on the running edge, which a run started from exited never passes through.
            if (root._deviceId !== _dump._device) Qt.callLater(root._listProfiles, false)
        }
    }

    BoundedProcess {
        id: _set
        timeoutMs: 5000
        onExited: (code) => {
            if (!_set.completedSuccessfully(code)) root._finishSwitch(false)
            else {
                root._setSucceeded = true
                root._observeSwitch()
            }
        }
    }
}
