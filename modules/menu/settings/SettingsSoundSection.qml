import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: 0

    // Device models contain live PwNodes, which a profile switch destroys. Empty models
    // close the pickers while their fallback labels keep the held device names visible.
    SectionLabel { label: "OUTPUT"; first: true }
    SettingsCard {
        SelectRow {
            glyph: "󰓃"
            label: Audio.ready ? Audio.sinkName : "No output device"
            description: "Output device"
            enabled: Audio.ready
            currentValue: Audio.sink
            model: Audio.switching ? [] : Audio.sinkModel
            // currentValue is a PwNode, the first object-valued SelectRow consumer:
            // the default fallbackLabel is String(currentValue), which renders QObject
            // junk if the model and the default node disagree for a beat while
            // PipeWire reattaches its node list
            fallbackLabel: Audio.ready ? Audio.sinkName : ""
            onChosen: (v) => Audio.setSink(v)
        }
        // held open through a switch, while the headset's sink is briefly gone
        CollapsibleSection {
            expanded: AudioMode.available || AudioMode.switching
            DescribedChipRow {
                glyph: "󰋎"
                title: "Mode"
                description: AudioMode.mode === "calls" ? "Lo-fi · mic on" : "Hi-fi · no mic"
                currentValue: AudioMode.mode
                model: [
                    { value: "listening", label: "Listening" },
                    { value: "calls",     label: "Calls" }
                ]
                onChosen: (v) => AudioMode.setMode(v)
            }
        }
        SliderRow {
            glyph: Audio.icon
            label: "Volume"
            enabled: Audio.ready
            value: Audio.uiVolume
            onChanged: (v) => Audio.setVolume(v)
        }
        ToggleRow {
            glyph: "󰖁"; label: "Mute"
            enabled: Audio.ready
            checked: Audio.muted
            onToggled: Audio.toggleMute()
        }
    }

    SectionLabel { label: "INPUT" }
    SettingsCard {
        SelectRow {
            glyph: "󰍬"
            label: Audio.sourceReady ? Audio.sourceName : "No input device"
            description: Audio.sourceReady
                ? "Input device" + (Audio.micInUse ? " · in use" : "")
                : ""
            enabled: Audio.sourceReady
            currentValue: Audio.source
            model: Audio.switching ? [] : Audio.sourceModel
            // same PwNode-valued fallback contract as the output row above
            fallbackLabel: Audio.sourceReady ? Audio.sourceName : ""
            onChosen: (v) => Audio.setSource(v)
            // an open capture stream is a privacy fact, so it gets a color cue too --
            // redundant with the "in use" text above, never the only signal
            statusDot: Audio.micInUse ? Theme.success : "transparent"
        }
        SliderRow {
            glyph: Audio.sourceUiMuted ? "󰍭" : "󰍬"
            label: "Volume"
            enabled: Audio.sourceReady
            value: Audio.sourceVolume
            onChanged: (v) => Audio.setSourceVolume(v)
        }
        ToggleRow {
            glyph: "󰍭"; label: "Mute"
            enabled: Audio.sourceReady
            checked: Audio.sourceUiMuted
            onToggled: Audio.toggleSourceMute()
        }
    }

    SectionLabel { label: "ROUTING" }
    SettingsCard {
        ControlRow {
            glyph: "󰒓"
            title: "Advanced settings"
            status: SystemTools.hasPwvucontrol
                ? "Volumes, profiles, and ports"
                : "pwvucontrol not installed"
            valueText: "󰅂"
            available: SystemTools.hasPwvucontrol
            onActivated: SystemTools.runOrNotify(["pwvucontrol"], "pwvucontrol failed to open")
        }
    }
}
