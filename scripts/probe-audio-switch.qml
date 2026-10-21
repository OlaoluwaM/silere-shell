import QtQuick
import Quickshell
import "services"
import "fake-pipewire"

ShellRoot {
    id: root

    property int phase: 0
    property int waited: 0
    property int failures: 0
    property var headset: null
    property var laptop: null
    property var mic: null
    property var replacementMic: null
    property var returned: null
    readonly property bool baseline: typeof Audio.beginProfileSwitch !== "function"

    Component {
        id: audioFactory
        QtObject {
            property real volume: 0
            property bool muted: false
            property int writes: 0
            signal volumesChanged()
            onVolumeChanged: { writes++; volumesChanged() }
            onMutedChanged: writes++
        }
    }
    Component {
        id: nodeFactory
        QtObject {
            property int nodeId: 0
            readonly property int id: nodeId
            property bool ready: true
            property string name: ""
            property string description: name
            property string nickname: ""
            property bool isSink: true
            property bool isStream: false
            property int type: 0
            property var audio: null
            property var properties: ({})
        }
    }

    function node(id: int, serial: string, device: string, label: string, volume: real, profile: string): var {
        const audio = audioFactory.createObject(root, { volume })
        audio.writes = 0
        return nodeFactory.createObject(root, {
            nodeId: id, name: label, audio,
            properties: { "device.id": device, "object.serial": serial,
                "device.api": device === "12" ? "bluez5" : "alsa",
                "api.bluez5.profile": profile }
        })
    }
    function check(ok: bool, label: string): void {
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }
    function closeTo(actual: real, wanted: real): bool {
        return Math.abs(actual - wanted) < 0.001
    }
    function held(volume: real): void {
        root.check(Audio.ready && root.closeTo(Audio.uiVolume, volume)
            && Audio.sinkName === "Headset", "bar/Home Audio display holds headset volume and name (got "
                + Audio.uiVolume + ", " + Audio.sinkName + ")")
    }
    function seed(): void {
        AudioMode._listedDevice = "12"
        AudioMode._listeningIndex = 1
        AudioMode._callsIndex = 2
    }
    function finish(): void {
        console.log("PROBE-AUDIO-SWITCH " + (root.failures ? "failed" : "passed"))
        ticks.stop()
    }

    Timer {
        id: ticks
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            switch (root.phase++) {
            case 0:
                root.headset = root.node(77, "100", "12", "Headset", 0.35, "a2dp-sink")
                root.laptop = root.node(78, "101", "13", "Laptop", 0.9, "")
                root.mic = root.node(88, "200", "13", "Microphone", 0.55, "")
                root.mic.isSink = false
                root.mic.type = PwNodeType.AudioSource
                Pipewire.defaultAudioSink = root.headset
                Pipewire.defaultAudioSource = root.mic
                break
            case 1:
                root.seed()
                root.check(AudioMode.available, "seeded real profile controller is available")
                AudioMode.setMode("calls")
                root.check(AudioMode.switching, "setMode begins a switch before the process exits")
                // The baseline follows the existing public entry point and fails on the
                // actual fallback value before testing APIs introduced by the fix.
                Pipewire.defaultAudioSink = root.baseline ? root.laptop : null
                Pipewire.defaultAudioSource = null
                break
            case 2:
                root.held(0.35)
                if (root.baseline) { root.finish(); return }
                root.check(Audio.sourceReady && root.closeTo(Audio.sourceVolume, 0.55),
                    "source display stays ready while its live node is absent")
                root.check(!Audio.sinkReady && !Audio.sourceNodeReady, "raw readiness remains live")
                root.returned = root.node(77, "102", "12", "Headset", 0.8, "headset-head-unit")
                Pipewire.defaultAudioSink = root.returned
                break
            case 3:
                root.held(0.35)
                root.check(AudioMode.switching, "a replacement without a fallback cannot complete")
                Pipewire.defaultAudioSink = null
                break
            case 4:
                Pipewire.defaultAudioSink = root.returned
                break
            case 5:
                root.check(AudioMode.switching, "a null default never counts as an observed fallback")
                root.held(0.35)
                Pipewire.defaultAudioSink = root.laptop
                root.replacementMic = root.node(88, "201", "13", "Microphone", 0.7, "")
                root.replacementMic.isSink = false
                root.replacementMic.type = PwNodeType.AudioSource
                root.replacementMic.audio.muted = true
                root.replacementMic.audio.writes = 0
                Pipewire.defaultAudioSource = root.replacementMic
                Pipewire.nodes = { values: [{ type: PwNodeType.AudioInStream }] }
                break
            case 6:
                root.held(0.35)
                root.check(Audio.sourceMuted && Audio.micInUse, "privacy reads the live replacement microphone")
                root.check(!Audio.sourceUiMuted && root.closeTo(Audio.sourceVolume, 0.55),
                    "source controls retain their held display independently of privacy")
                Audio.setVolume(0.6)
                Audio.toggleMute()
                Audio.bumpBy(Audio.stepPct)
                root.check(!Audio.muted && root.closeTo(Audio.effectiveVolume, 0.65),
                    "volume keys step from the held effective volume while muted")
                Audio.setVolume(0.4)
                Audio.toggleMute()
                Audio.setSourceVolume(0.2)
                Audio.toggleSourceMute()
                root.check(Audio.muted && root.closeTo(Audio.effectiveVolume, 0.4),
                    "queued output volume and mute preserve user order")
                root.check(root.laptop.audio.writes === 0 && root.replacementMic.audio.writes === 0,
                    "held edits never write through fallback nodes")
                Pipewire.defaultAudioSink = root.node(77, "100", "12", "Headset", 0.8, "headset-head-unit")
                break
            case 7:
                root.check(AudioMode.switching, "the original object serial cannot complete after fallback")
                root.returned = root.node(77, "103", "12", "Headset", 0.8, "headset-head-unit")
                root.returned.ready = false
                Pipewire.defaultAudioSink = root.returned
                break
            case 8:
                root.check(AudioMode.switching, "an unready replacement cannot complete")
                root.returned.ready = true
                break
            case 9:
                root.check(AudioMode.switching, "a ready replacement waits for successful process exit")
                Quickshell.execDetached(["touch", Quickshell.env("SILERE_AUDIO_SWITCH_ROOT") + "/release"])
                break
            case 10:
                if (AudioMode.switching && ++root.waited < 25) { root.phase--; return }
                root.check(!AudioMode.switching && !Audio.switching,
                    "a ready new serial completes even when the numeric node ID is reused")
                if (AudioMode.switching) { root.finish(); return }
                root.check(root.closeTo(root.returned.audio.volume, 0.4) && root.returned.audio.muted,
                    "queued output volume and mute replay on the validated replacement")
                root.check(root.closeTo(root.replacementMic.audio.volume, 0.7)
                    && root.replacementMic.audio.writes === 0,
                    "a reused mic ID and label with a new serial receives no queued edits")
                root.headset = root.node(77, "104", "12", "Headset", 0.25, "a2dp-sink")
                Pipewire.defaultAudioSink = root.headset
                break
            case 11:
                root.seed()
                AudioMode.setMode("calls")
                root.returned = root.node(77, "105", "12", "Headset", 0.45, "headset-head-unit")
                Pipewire.defaultAudioSink = root.returned
                Pipewire.defaultAudioSource = null
                root.waited = 0
                break
            case 12:
                if (!AudioMode._setSucceeded && ++root.waited < 25) { root.phase--; return }
                root.check(AudioMode._setSucceeded && AudioMode.switching,
                    "a new ready serial without fallback holds after successful process exit")
                root.held(0.25)
                Pipewire.defaultAudioSink = null
                break
            case 13:
                Pipewire.defaultAudioSink = root.returned
                break
            case 14:
                root.check(AudioMode.switching,
                    "a null default does not complete a successful switch as a fallback")
                Pipewire.defaultAudioSink = root.laptop
                break
            case 15:
                Pipewire.defaultAudioSink = root.returned
                root.waited = 0
                break
            case 16:
                if (AudioMode.switching && ++root.waited < 25) { root.phase--; return }
                root.check(!AudioMode.switching && !Audio.switching && !Audio.sourceReady,
                    "a validated output completes without waiting for a missing microphone")
                if (AudioMode.switching) { root.finish(); return }
                root.check(root.closeTo(Audio.uiVolume, 0.45),
                    "completion without queued output edits accepts the new live volume")
                root.headset = root.node(77, "106", "12", "Headset", 0.25, "a2dp-sink")
                Pipewire.defaultAudioSink = root.headset
                break
            case 17:
                root.seed()
                AudioMode._callsIndex = 9
                AudioMode.setMode("calls")
                Pipewire.defaultAudioSink = root.laptop
                Audio.setVolume(0.22)
                root.waited = 0
                break
            case 18:
                if (AudioMode.switching && ++root.waited < 25) { root.phase--; return }
                root.check(!AudioMode.switching && !Audio.switching && root.closeTo(Audio.uiVolume, 0.9),
                    "a failed profile process releases the shared hold")
                root.check(root.laptop.audio.writes === 0, "failure discards queued output edits")
                Pipewire.defaultAudioSink = root.headset
                break
            case 19:
                root.seed()
                AudioMode.setMode("calls")
                Pipewire.defaultAudioSink = root.laptop
                Pipewire.defaultAudioSource = null
                Audio.setVolume(0.1)
                root.waited = 0
                break
            case 20:
                if (AudioMode.switching && ++root.waited < 25) { root.phase--; return }
                root.check(!AudioMode.switching && !Audio.switching && !Audio.sourceReady,
                    "the two-second backstop releases even without a source")
                root.check(root.laptop.audio.writes === 0 && root.closeTo(Audio.uiVolume, 0.9),
                    "the backstop discards edits instead of writing the fallback")
                Pipewire.defaultAudioSource = root.replacementMic
                SystemTools.hasWpctl = false
                break
            case 21:
                Audio.beginProfileSwitch()
                Audio.setSourceVolume(0.3)
                Audio.toggleSourceMute()
                root.check(root.replacementMic.audio.writes === 0,
                    "a stable external microphone also defers edits during the hold")
                Audio.endProfileSwitch(true)
                break
            case 22:
                root.check(root.closeTo(root.replacementMic.audio.volume, 0.3)
                    && !root.replacementMic.audio.muted,
                    "the same external microphone receives queued volume and mute on success")
                root.finish()
                break
            }
        }
    }
}
