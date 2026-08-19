import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "OUTPUT"; first: true }
    SettingsCard {
        SelectRow {
            glyph: "󰓃"
            label: Audio.ready ? Audio.sinkName : "No output device"
            description: "Output device"
            enabled: Audio.ready
            currentValue: Audio.sink
            model: Audio.sinkModel
            // currentValue is a PwNode, the first object-valued SelectRow consumer:
            // the default fallbackLabel is String(currentValue), which renders QObject
            // junk if the model and the default node disagree for a beat while
            // PipeWire reattaches its node list
            fallbackLabel: Audio.ready ? Audio.sinkName : ""
            onChosen: (v) => Audio.setSink(v)
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
            label: Audio.sourceReady ? Audio.sourceLabel(Audio.source) : "No input device"
            description: Audio.sourceReady
                ? "Input device" + (Audio.micInUse ? " · in use" : "")
                : ""
            enabled: Audio.sourceReady && Audio.sourceCount > 0
            currentValue: Audio.source
            model: Audio.sourceModel
            // same PwNode-valued fallback contract as the output row above
            fallbackLabel: Audio.sourceReady ? Audio.sourceLabel(Audio.source) : ""
            onChosen: (v) => Audio.setSource(v)
            // an open capture stream is a privacy fact, so it gets a color cue too --
            // redundant with the "in use" text above, never the only signal
            statusDot: Audio.micInUse ? Theme.success : "transparent"
        }
        SliderRow {
            glyph: Audio.sourceMuted ? "󰍭" : "󰍬"
            label: "Volume"
            enabled: Audio.sourceReady
            value: Audio.sourceVolume
            onChanged: (v) => Audio.setSourceVolume(v)
        }
        ToggleRow {
            glyph: "󰍭"; label: "Mute"
            enabled: Audio.sourceReady
            checked: Audio.sourceMuted
            onToggled: Audio.toggleSourceMute()
        }
    }

    SectionLabel { label: "ROUTING" }
    SettingsCard {
        ControlRow {
            glyph: "󰒓"
            title: "Advanced settings"
            status: SystemTools.hasPwvucontrol
                ? "Per-app volumes, profiles, and ports in pwvucontrol"
                : "pwvucontrol not installed"
            valueText: "󰅂"
            available: SystemTools.hasPwvucontrol
            onActivated: SystemTools.runOrNotify(["pwvucontrol"], "pwvucontrol failed to open")
        }
    }
}
