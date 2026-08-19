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
    readonly property bool ready: Pipewire.ready && sink !== null && sink.ready && audio !== null

    // Default SOURCE (mic). sourceMuted stays a direct read for the privacy chip
    // (see the mic write path below, which is a light one -- no pending/reconcile
    // ladder like the sink's mute/volume machinery above).
    readonly property PwNode      source:      Pipewire.defaultAudioSource
    readonly property PwNodeAudio sourceAudio: source ? source.audio : null
    readonly property bool sourceMuted: sourceAudio ? sourceAudio.muted : false
    // source.ready is part of the gate for the same reason it is in `ready` above: the
    // audio interface object exists the instant the node does, before PipeWire finishes
    // binding it, and the mic write paths below must not write through that window
    readonly property bool sourceReady: Pipewire.ready && source !== null && source.ready
        && sourceAudio !== null
    readonly property real sourceVolume: root._clampVolume(sourceReady ? sourceAudio.volume : 0)

    property real targetVolume: ready ? root._clampVolume(audio.volume) : 0
    property bool pendingApply: false
    property bool _componentReady: false

    readonly property real effectiveVolume: root._clampVolume(
        pendingApply ? targetVolume : (ready ? audio.volume : 0))
    property bool _pendingMuted: false
    property bool _desiredMuted: false
    property bool _muteWritePending: false
    readonly property int _maxConfirmRetries: 6
    readonly property real _volumeEpsilon: 0.005
    readonly property real _confirmTolerance: Math.max(_volumeEpsilon, stepPct * 0.5)
    property int _volRetries: 0
    property int _muteRetries: 0
    readonly property bool muted: ready ? _pendingMuted : false
    readonly property real uiVolume: root._clampVolume(muted ? 0 : effectiveVolume)

    readonly property string icon:
        !ready                   ? "󰝟" :
        muted || uiVolume === 0  ? "󰖁" :
        uiVolume < 0.33          ? "󰕿" :
        uiVolume < 0.66          ? "󰖀" : "󰕾"
    readonly property string label: ready ? `${Math.round(uiVolume * 100)}%` : "--%"
    readonly property string sinkName: root.sinkLabel(sink)

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
    readonly property int sinkCount: sinks.length

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
    readonly property int sourceCount: sources.length

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
        if (node) Pipewire.preferredDefaultAudioSink = node
    }

    function setSource(node): void {
        if (node) Pipewire.preferredDefaultAudioSource = node
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

    // Mic control is deliberately lighter than the sink's: it keeps the frame
    // throttle (the settings slider emits per mouse-move, exactly the drag spam
    // the sink's writeThrottle exists for) but not the pending-confirm/retry
    // ladder -- that half guards the sink's volume limit and hardware-key racing,
    // neither of which the mic path has. Grow it the ladder only if real usage
    // shows PipeWire fighting these writes too -- the symptom to watch for is the
    // mic handle snapping through stale intermediate positions right after a fast
    // drag releases, which is exactly what the sink's pendingApply masking hides.
    property real _sourcePendingVolume: 0
    Timer {
        id: sourceWriteThrottle
        interval: 16
        repeat: false
        onTriggered: {
            const a = root.sourceAudio
            if (!a) return
            if (Math.abs(a.volume - root._sourcePendingVolume) >= root._volumeEpsilon)
                a.volume = root._sourcePendingVolume
        }
    }

    function setSourceVolume(v: real): void {
        if (!root.sourceReady) return
        root._sourcePendingVolume = root._clampVolume(v)
        if (!sourceWriteThrottle.running) {
            sourceAudio.volume = root._sourcePendingVolume
            sourceWriteThrottle.restart()
        }
    }

    function toggleSourceMute(): void {
        if (!root.sourceReady) return
        sourceAudio.muted = !sourceAudio.muted
    }

    function _clampVolume(v: real): real {
        if (!isFinite(v)) return 0
        return Math.max(0, Math.min(1.0, v))
    }

    function _enforceVolumeLimit(): void {
        const a = ready ? audio : null
        if (!a) return
        const clamped = _clampVolume(a.volume)
        if (Math.abs(a.volume - clamped) >= _volumeEpsilon) _writeVolume(clamped)
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
        const a = ready ? audio : null
        targetVolume = a ? _clampVolume(a.volume) : 0
        _pendingMuted = a ? a.muted : false
        _desiredMuted = _pendingMuted
        _muteWritePending = false
        _volRetries = 0
        _muteRetries = 0
        if (a) Qt.callLater(root._enforceVolumeLimit)
    }
    onAudioChanged: _syncAudio()
    onReadyChanged: _syncAudio()
    Component.onCompleted: {
        _componentReady = true
        _syncAudio()
    }

    Connections {
        target: root.audio
        enabled: root.ready
        function onVolumesChanged() {
            const a = root.audio
            if (!a) return
            const actual = a.volume
            const clamped = root._clampVolume(actual)
            if (Math.abs(actual - clamped) >= root._volumeEpsilon) {
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
            if (Math.abs(a.volume - root.targetVolume) >= root._volumeEpsilon)
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
            if (Math.abs(actual - root.targetVolume) > root._confirmTolerance) {
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

    function bumpBy(delta: real): void {
        const a = ready ? audio : null
        if (!a || delta === 0) return
        if (_pendingMuted) unmute()
        let v = pendingApply ? targetVolume : _clampVolume(a.volume)
        _writeVolume(v + delta)
    }

    function setVolume(v: real): void {
        if (!ready || !audio) return
        if (_pendingMuted && v > 0) unmute()
        _writeVolume(v)
    }

    function _writeVolume(v: real): void {
        const a = ready ? audio : null
        if (!a) return
        v = _clampVolume(v)
        if (Math.abs(v - targetVolume) < _volumeEpsilon && pendingApply) return
        if (!pendingApply && Math.abs(v - _clampVolume(a.volume)) < _volumeEpsilon) return
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
        if (!ready || !audio) return
        const wasMuted = _pendingMuted
        _setMuted(!wasMuted)
    }

    function unmute(): void {
        if (!ready || !audio || !_pendingMuted) return
        _setMuted(false)
    }

    function _setMuted(shouldMute: bool): void {
        const a = ready ? audio : null
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
