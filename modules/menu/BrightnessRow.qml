pragma ComponentBehavior: Bound

import QtQuick
import "../../services"
import "controls"

LevelRow {
    id: root

    glyph: Brightness.icon
    accessibleName: "Brightness"
    wheelKey: "brightness"
    value: Brightness.pendingPercent / 100
    valueText: Brightness.pendingPercent + "%"
    expandable: Brightness.devices.length > 1
    options: Brightness.deviceChoices
    currentValue: Brightness.deviceChoice

    function glyphFor(option: var): string {
        return option.value === "" ? "󰘸" : "󰃟"
    }

    onMoved: value => Brightness.setPercent(Math.round(value * 100))
    onOptionChosen: value => ShellSettings.brightnessDevice = value

    Connections {
        target: Brightness
        function onDevicesChanged(): void {
            if (Brightness.devices.length <= 1) root.closeInline()
        }
    }
}
