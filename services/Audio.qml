pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property real stepPct: 0.05

    // fires on every raise/lower, even when bumpBy() can't move the value (already
    // at 0% or 100%) -- the OSD still needs to show *something* for the keypress
    signal volumeNudged()

    readonly property PwNode     sink:  Pipewire.defaultAudioSink
    readonly property PwNodeAudio audio: sink ? sink.audio : null
    readonly property bool sinkReady: Pipewire.ready && sink !== null && sink.ready && audio !== null
    readonly property bool ready: root.switching ? root._profileHold.ready : root.sinkReady

    // Privacy follows the live mic even while the Sound page holds its controls.
    readonly property PwNode      source:      Pipewire.defaultAudioSource
    readonly property PwNodeAudio sourceAudio: source ? source.audio : null
    readonly property bool sourceMuted: sourceAudio ? sourceAudio.muted : false
    // source.ready is part of the gate for the same reason it is in sinkReady: the
    // audio interface object exists the instant the node does, before PipeWire finishes
    // binding it, and the mic write paths below must not write through that window
    readonly property bool sourceNodeReady: Pipewire.ready && source !== null && source.ready
        && sourceAudio !== null
    readonly property bool sourceReady: root.switching ? root._profileHold.sourceReady : root.sourceNodeReady
    readonly property real sourceVolume: root.switching ? root._profileHold.sourceVolume
        : root._clampVolume(root._sourceWpctlShown >= 0 ? root._sourceWpctlShown
            : sourceNodeReady && sourceAudio ? sourceAudio.volume : 0)
    readonly property bool sourceUiMuted: root.switching ? root._profileHold.sourceMuted : root.sourceMuted
    readonly property string sourceName: root.switching ? root._profileHold.sourceName : root.sourceLabel(source)

    // audio can notify null before ready re-evaluates, so guard it directly
    property real targetVolume: sinkReady && audio ? root._clampVolume(audio.volume) : 0
    property bool pendingApply: false
    property bool _componentReady: false

    readonly property real effectiveVolume: root.switching ? root._profileHold.volume : root._clampVolume(
        pendingApply ? targetVolume : (sinkReady && audio ? audio.volume : 0))
    property bool _pendingMuted: false
    property bool _desiredMuted: false
    property bool _muteWritePending: false
    readonly property int _maxConfirmRetries: 6
    readonly property real _volumeEpsilon: 0.005
    readonly property real _confirmTolerance: Math.max(_volumeEpsilon, stepPct * 0.5)
    property int _volRetries: 0
    property int _muteRetries: 0
    readonly property bool muted: root.switching ? root._profileHold.muted : sinkReady ? _pendingMuted : false
    readonly property real uiVolume: root._clampVolume(muted ? 0 : effectiveVolume)

    readonly property string icon:
        !ready                   ? "󰝟" :
        muted || uiVolume === 0  ? "󰖁" :
        uiVolume < 0.33          ? "󰕿" :
        uiVolume < 0.66          ? "󰖀" : "󰕾"
    readonly property string label: ready ? `${Math.round(uiVolume * 100)}%` : "--%"
    readonly property string sinkName: root.switching ? root._profileHold.sinkName : root.sinkLabel(sink)

    readonly property var sinks: {
        const out = []
        // PipeWire briefly detaches its node model while reconnecting.
        const all = Pipewire.nodes ? (Pipewire.nodes.values || []) : []
        for (let i = 0; i < all.length; i++) {
            const n = all[i]
            if (n && n.isSink && !n.isStream) out.push(n)
        }
        return out
    }
    readonly property int sinkCount: root.switching ? root._profileHold.sinkCount : sinks.length

    readonly property var sinkModel: sinks.map(n => ({ value: n, label: root.sinkLabel(n) }))

    readonly property var sources: {
        const out = []
        // PipeWire briefly detaches its node model while reconnecting.
        const all = Pipewire.nodes ? (Pipewire.nodes.values || []) : []
        for (let i = 0; i < all.length; i++) {
            const n = all[i]
            // no isSource convenience flag exists (only isSink does) -- classify by
            // the AudioSource type bit instead, then drop the monitor-of-a-sink
            // nodes PipeWire auto-creates for every sink: those carry the same
            // AudioSource bit but are always named "<sink-name>.monitor", and the
            // sink side has no equivalent synthetic entry to filter
            if (n && !n.isStream
                    && (n.type & PwNodeType.AudioSource) === PwNodeType.AudioSource
                    && !n.name.endsWith(".monitor"))
                out.push(n)
        }
        return out
    }
    readonly property var sourceModel: sources.map(n => ({ value: n, label: root.sourceLabel(n) }))

    // "mic in use" means an app has an open capture stream, not that a source device
    // merely exists -- PwNodeType.AudioInStream is Quickshell's own classification of a
    // PipeWire node whose media.class is Stream/Input/Audio (a stream node capturing
    // from a source), which only exists on the graph while something is recording it
    readonly property bool micInUse: {
        const all = Pipewire.nodes ? (Pipewire.nodes.values || []) : []
        for (let i = 0; i < all.length; i++) {
            const n = all[i]
            if (n && (n.type & PwNodeType.AudioInStream) === PwNodeType.AudioInStream) return true
        }
        return false
    }

    // Both nodes must be bound here -- Quickshell only keeps a PwNode's properties
    // (audio.muted included) live once it's listed in a PwObjectTracker, otherwise the
    // node sits unbound and sourceMuted/audio would silently stop tracking PipeWire.
    PwObjectTracker {
        objects: (root.sink ? [root.sink] : []).concat(root.source ? [root.source] : [])
    }

    function setSink(node): void {
        if (!root.switching && node) Pipewire.preferredDefaultAudioSink = node
    }

    function setSource(node): void {
        if (!root.switching && node) Pipewire.preferredDefaultAudioSource = node
    }

    function nodeLabel(node, fallback: string): string {
        if (!node) return ""
        return SafeText.singleLineText(
            node.description || node.nickname || node.name || fallback, 256)
    }

    function sinkLabel(node): string {
        return root.nodeLabel(node, "Output")
    }

    function sourceLabel(node): string {
        return root.nodeLabel(node, "Input")
    }

    // Profile changes replace nodes and briefly route defaults elsewhere. One scalar
    // snapshot keeps every volume surface steady; live node references remain separate.
    property var _profileHold: null
    readonly property bool switching: root._profileHold !== null

    function nodeSerial(node): string {
        return node && node.ready ? String(node.properties["object.serial"] ?? "") : ""
    }

    function beginProfileSwitch(): void {
        if (root.switching || !root.sinkReady) return
        root._profileHold = {
            ready: root.ready, volume: root.effectiveVolume, muted: root.muted,
            sinkName: root.sinkName, sinkCount: root.sinkCount,
            volumeRequested: root.pendingApply, muteRequested: root._muteWritePending,
            sourceReady: root.sourceReady, sourceVolume: root.sourceVolume,
            sourceMuted: root.sourceMuted, sourceName: root.sourceName,
            sourceSerial: root.nodeSerial(root.source),
            sourceVolumeRequested: root._sourceWpctlShown >= 0 || sourceWriteThrottle.running,
            sourceMuteRequested: false
        }
        // A delayed write must not follow the default onto the fallback device.
        writeThrottle.stop()
        pendingSafety.stop()
        muteSafety.stop()
        root.pendingApply = false
        root._muteWritePending = false
        sourceWriteThrottle.stop()
        sourceWpctlGap.stop()
        root._sourceWpctlPending = -1
    }

    function endProfileSwitch(apply: bool): void {
        const held = root._profileHold
        if (!held) return
        root._syncAudio()
        if (apply && root.sinkReady) {
            if (held.volumeRequested) root._writeVolume(held.volume)
            if (held.muteRequested) root._setMuted(held.muted)
        }
        // The input may legitimately stay external or disappear in Listening mode.
        // A label or reusable object id cannot identify the mic the user adjusted.
        if (apply && root.sourceNodeReady && held.sourceSerial !== ""
                && root.nodeSerial(root.source) === held.sourceSerial) {
            if (held.sourceVolumeRequested) root._writeSourceVolume(held.sourceVolume)
            if (held.sourceMuteRequested) root.sourceAudio.muted = held.sourceMuted
        }
        root._profileHold = null
        Qt.callLater(root._enforceVolumeLimit)
    }

    // Mic control is deliberately lighter than the sink's: both of its write paths keep a
    // frame gap between writes (the settings slider emits per mouse-move, exactly the drag
    // spam the sink's writeThrottle exists for), but neither has the sink's retry ladder --
    // that guards the sink's volume limit and hardware-key racing, neither of which the mic
    // path has. This in-process one is for a system without wpctl.
    property real _sourcePendingVolume: 0
    Timer {
        id: sourceWriteThrottle
        interval: 16
        repeat: false
        onTriggered: {
            const a = root.sourceNodeReady ? root.sourceAudio : null
            if (!a) return
            if (Math.abs(a.volume - root._sourcePendingVolume) >= root._volumeEpsilon)
                a.volume = root._sourcePendingVolume
        }
    }

    // Quickshell 0.3.1 skips a volume write to a device-routed node whose route reports no
    // volume step, yet keeps the new value as if it landed, so the slider shows it until the
    // device's next route update snaps it back. A Bluetooth headset's call-mode mic is one,
    // and QML cannot see which other mics are, so every mic write goes through wpctl when it
    // is installed, one run at a time with the latest kept. A queued value keeps the mic it
    // was meant for, so a default that moves meanwhile never takes it. Runs start a frame
    // apart: one started straight from exited would keep the previous run's timeout, which
    // BoundedProcess arms on the running edge. Until PipeWire reports the asked-for level
    // back, sourceVolume shows it, or an earlier run's echo would pull the slider back
    // between wheel steps.
    readonly property bool _sourceViaWpctl: root.sourceNodeReady && SystemTools.hasWpctl
    property real _sourceWpctlPending: -1
    property string _sourceWpctlSerial: ""
    property real _sourceWpctlShown: -1
    BoundedProcess {
        id: sourceWpctl
        timeoutMs: 3000
        // wpctl parses the value with the C library, so a comma-decimal locale would misread it
        environment: ({ "LC_ALL": "C" })
        onExited: {
            // a slow final run would otherwise use up the shown level's backstop
            sourceWpctlConfirm.restart()
            if (root._sourceWpctlPending >= 0) sourceWpctlGap.restart()
        }
    }
    Timer {
        id: sourceWpctlGap
        interval: 16
        onTriggered: root._flushSourceWpctl()
    }
    // an echo that never comes (a run that failed) must not pin the shown level
    Timer {
        id: sourceWpctlConfirm
        interval: 800
        onTriggered: root._sourceWpctlShown = -1
    }
    Connections {
        target: root.sourceNodeReady ? root.sourceAudio : null
        function onVolumesChanged() {
            if (root._sourceWpctlShown < 0 || sourceWpctl.running || sourceWpctlGap.running
                    || root._sourceWpctlPending >= 0) return
            if (Math.abs(root.sourceAudio.volume - root._sourceWpctlShown) < root._confirmTolerance) {
                sourceWpctlConfirm.stop()
                root._sourceWpctlShown = -1
            }
        }
    }
    onSourceChanged: {
        sourceWriteThrottle.stop()
        sourceWpctlGap.stop()
        root._sourceWpctlPending = -1
        sourceWpctlConfirm.stop()
        root._sourceWpctlShown = -1
    }
    function _flushSourceWpctl(): void {
        if (sourceWpctl.running || sourceWpctlGap.running || root._sourceWpctlPending < 0) return
        const v = root._sourceWpctlPending
        root._sourceWpctlPending = -1
        if (!root._sourceViaWpctl
                || root.nodeSerial(root.source) !== root._sourceWpctlSerial) return
        sourceWpctl.exec(["wpctl", "set-volume", String(root.source.id), v.toFixed(3)])
    }

    function setSourceVolume(v: real): void {
        if (!root.sourceReady) return
        if (root.switching) {
            root._profileHold = Object.assign({}, root._profileHold,
                { sourceVolume: root._clampVolume(v), sourceVolumeRequested: true })
            return
        }
        root._writeSourceVolume(v)
    }

    function _writeSourceVolume(v: real): void {
        if (!root.sourceNodeReady) return
        if (root._sourceViaWpctl) {
            root._sourceWpctlPending = root._clampVolume(v)
            root._sourceWpctlSerial = root.nodeSerial(root.source)
            root._sourceWpctlShown = root._sourceWpctlPending
            sourceWpctlConfirm.restart()
            root._flushSourceWpctl()
            return
        }
        root._sourcePendingVolume = root._clampVolume(v)
        if (!sourceWriteThrottle.running) {
            sourceAudio.volume = root._sourcePendingVolume
            sourceWriteThrottle.restart()
        }
    }

    function toggleSourceMute(): void {
        if (!root.sourceReady) return
        if (root.switching) {
            root._profileHold = Object.assign({}, root._profileHold,
                { sourceMuted: !root.sourceUiMuted, sourceMuteRequested: true })
            return
        }
        sourceAudio.muted = !sourceAudio.muted
    }

    function _clampVolume(v: real): real {
        if (!isFinite(v)) return 0
        return Math.max(0, Math.min(1.0, v))
    }

    function _volumeMatches(actual: real, wanted: real): bool {
        return isFinite(actual) && Math.abs(actual - wanted) < _volumeEpsilon
    }

    function _enforceVolumeLimit(): void {
        if (root.switching) return
        const a = sinkReady ? audio : null
        if (!a) return
        const clamped = _clampVolume(a.volume)
        if (!_volumeMatches(a.volume, clamped)) _writeVolume(clamped)
    }

    function _acceptVolume(actual: real): void {
        targetVolume = _clampVolume(actual)
        pendingApply = false
        _volRetries = 0
        pendingSafety.stop()
    }

    function _syncAudio(): void {
        if (!_componentReady) return
        writeThrottle.stop()
        pendingSafety.stop()
        muteSafety.stop()
        pendingApply = false
        const a = sinkReady ? audio : null
        targetVolume = a ? _clampVolume(a.volume) : 0
        _pendingMuted = a ? a.muted : false
        _desiredMuted = _pendingMuted
        _muteWritePending = false
        _volRetries = 0
        _muteRetries = 0
        if (a) Qt.callLater(root._enforceVolumeLimit)
    }
    onAudioChanged: _syncAudio()
    onSinkReadyChanged: _syncAudio()
    Component.onCompleted: {
        _componentReady = true
        _syncAudio()
    }

    Connections {
        target: root.audio
        enabled: root.sinkReady && !root.switching
        function onVolumesChanged() {
            const a = root.audio
            if (!a) return
            const actual = a.volume
            const clamped = root._clampVolume(actual)
            if (!root._volumeMatches(actual, clamped)) {
                root._writeVolume(clamped)
                return
            }
            if (root.pendingApply
                    && Math.abs(clamped - root.targetVolume) <= root._confirmTolerance)
                root._acceptVolume(clamped)
            else if (!root.pendingApply)
                root.targetVolume = clamped
        }
        function onMutedChanged() {
            const a = root.audio
            if (!a) return
            if (root._muteWritePending) {
                if (a.muted === root._desiredMuted) {
                    root._pendingMuted = a.muted
                    root._muteWritePending = false
                    muteSafety.stop()
                }
                return
            }
            root._pendingMuted = a.muted
            root._desiredMuted = a.muted
        }
    }

    Timer {
        id: writeThrottle
        interval: 16
        repeat: false
        onTriggered: {
            const a = root.audio
            if (!a) return
            if (!root._volumeMatches(a.volume, root.targetVolume))
                a.volume = Math.max(0, Math.min(1.0, root.targetVolume))
        }
    }

    Timer {
        id: pendingSafety
        interval: 600
        onTriggered: {
            const a = root.audio
            if (!a || !root.pendingApply) return
            const actual = root._clampVolume(a.volume)
            if (!isFinite(a.volume) || Math.abs(a.volume - root.targetVolume) > root._confirmTolerance) {
                if (root._volRetries >= root._maxConfirmRetries) {
                    root._acceptVolume(actual)
                    return
                }
                root._volRetries++
                a.volume = Math.max(0, Math.min(1.0, root.targetVolume))
                pendingSafety.restart()
            } else {
                root._acceptVolume(actual)
            }
        }
    }

    Timer {
        id: muteSafety
        interval: 350
        onTriggered: {
            const a = root.audio
            if (!a || !root._muteWritePending) return
            if (a.muted === root._desiredMuted) {
                root._pendingMuted = a.muted
                root._muteWritePending = false
            } else if (root._muteRetries >= root._maxConfirmRetries) {
                root._pendingMuted = a.muted
                root._muteWritePending = false
            } else {
                root._muteRetries++
                a.muted = root._desiredMuted
                muteSafety.restart()
            }
        }
    }

    // a level set elsewhere rejoins the step grid on the first notch instead of staying off it
    function _stepFrom(v: real, delta: real): real {
        const notches = Math.round(delta / stepPct)
        if (notches === 0) return v + delta
        const at = v / stepPct
        const base = notches > 0 ? Math.floor(at + 0.01) : Math.ceil(at - 0.01)
        return (base + notches) * stepPct
    }

    function bumpBy(delta: real): void {
        if (root.switching) {
            if (delta === 0) return
            root.unmute()
            root.setVolume(root._stepFrom(root.effectiveVolume, delta))
            return
        }
        const a = sinkReady ? audio : null
        if (!a || delta === 0) return
        if (_pendingMuted) unmute()
        const v = pendingApply ? targetVolume : _clampVolume(a.volume)
        _writeVolume(root._stepFrom(v, delta))
    }

    function setVolume(v: real): void {
        if (root.switching) {
            v = root._clampVolume(v)
            root._profileHold = Object.assign({}, root._profileHold, {
                volume: v, volumeRequested: true,
                muted: v > 0 ? false : root.muted,
                muteRequested: root._profileHold.muteRequested || v > 0
            })
            return
        }
        if (!sinkReady || !audio) return
        if (_pendingMuted && v > 0) unmute()
        _writeVolume(v)
    }

    function _writeVolume(v: real): void {
        const a = sinkReady ? audio : null
        if (!a) return
        v = _clampVolume(v)
        if (Math.abs(v - targetVolume) < _volumeEpsilon && pendingApply) return
        if (!pendingApply && _volumeMatches(a.volume, v)) return
        targetVolume = v
        pendingApply = true

        if (!writeThrottle.running) {
            a.volume = v
            writeThrottle.restart()
        }
        _volRetries = 0
        pendingSafety.restart()
    }

    function toggleMute(): void {
        if (root.switching) {
            root._profileHold = Object.assign({}, root._profileHold,
                { muted: !root.muted, muteRequested: true })
            return
        }
        if (!sinkReady || !audio) return
        const wasMuted = _pendingMuted
        _setMuted(!wasMuted)
    }

    function unmute(): void {
        if (root.switching) {
            root._profileHold = Object.assign({}, root._profileHold,
                { muted: false, muteRequested: true })
            return
        }
        if (!sinkReady || !audio || !_pendingMuted) return
        _setMuted(false)
    }

    function _setMuted(shouldMute: bool): void {
        const a = sinkReady ? audio : null
        if (!a) return
        _desiredMuted = shouldMute
        _pendingMuted = shouldMute
        _muteWritePending = true
        _muteRetries = 0
        a.muted = shouldMute
        muteSafety.restart()
    }

    // hardware volume keys land here (nixos keybindings.nix binds XF86Audio*): going
    // through the shell instead of raw wpctl lets a keypress surface the OSD even at
    // the rails, where wpctl's write is a PipeWire no-op -- no property changes fire,
    // so OsdBarState never hears about it and the user presses a dead key with no
    // feedback. raise()/lower() emit volumeNudged() unconditionally, independent of
    // whether bumpBy() actually moved anything, so the OSD always has something to say.
    //
    // no bootstrap property needed: shell.qml eagerly references OsdBarState.activeCount
    // (the OSD popup's PopupLoader.wantOpen binding), and OsdBarState already carries a
    // top-level Connections{target: Audio} -- that binding alone drags this singleton
    // (and this IpcHandler) into existence at shell start, the same way MediaPopupState
    // bootstraps Media.
    IpcHandler {
        target: "audio"
        function raise(): void { root.bumpBy(root.stepPct); root.volumeNudged() }
        function lower(): void { root.bumpBy(-root.stepPct); root.volumeNudged() }
    }
}
