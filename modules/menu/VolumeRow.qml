pragma ComponentBehavior: Bound

import QtQuick
import "../../services"
import "controls"

LevelRow {
    id: root

    glyph: Audio.icon
    accessibleName: "Volume"
    wheelKey: "volume"
    value: Audio.uiVolume
    valueText: Audio.label
    glyphClickable: true
    expandable: Audio.sinkCount > 1
    toggleEnabled: !Audio.switching
    options: Audio.switching ? [] : Audio.sinkModel
    currentValue: Audio.sink

    function glyphFor(option: var): string { return "󰓃" }

    onGlyphClicked: Audio.toggleMute()
    onMoved: v => Audio.setVolume(v)
    onOptionChosen: value => Audio.setSink(value)

    Connections {
        target: Audio
        function onSwitchingChanged() { if (Audio.switching) root.closeInline() }
        function onSinkCountChanged() {
            if (Audio.sinkCount <= 1) root.closeInline()
        }
    }
}
