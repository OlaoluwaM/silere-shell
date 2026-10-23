pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../common"

// A QuickSlider that can open a list of devices underneath it. VolumeRow and BrightnessRow
// supply the device list and the bindings; the card sees this wrapper as one row.
// Not a MenuRow: that would paint a second hover band under the slider's own. The card
// writes the four geometry properties below, and the wrapper only forwards pointer state.
Item {
    id: root

    property bool open: false
    property real topRadius: 0
    property real bottomRadius: 0
    property real cardInset: 1
    property real cardLeftBleed: 0
    property bool reserveExpandSlot: false
    // the card treats this wrapper as a row, but only the slider underneath tracks the pointer
    readonly property bool rowHovered:     _slider.rowHovered
    readonly property bool rowPressed:     _slider.rowPressed
    readonly property bool rowInteractive: _slider.rowInteractive

    property alias glyph: _slider.glyph
    property alias accessibleName: _slider.accessibleName
    property alias wheelKey: _slider.wheelKey
    property alias value: _slider.value
    property alias valueText: _slider.valueText
    property alias glyphClickable: _slider.glyphClickable
    property alias expandable: _slider.expandable
    // a device switch in flight can veto the chevron without hiding it
    property bool toggleEnabled: true

    // each option is { value, label }; the one equal to currentValue wears the check
    property var options: []
    property var currentValue

    signal moved(real value)
    signal glyphClicked()
    signal optionChosen(var value)

    // each row names the glyph for one of its options; the list has no glyph data of its own
    function glyphFor(option: var): string { return "" }

    width: parent ? parent.width : 0
    implicitHeight: _slider.height + _options.height
    height: implicitHeight
    readonly property bool _optionsShown: root.open || _options.height > 0.5

    function closeInline(): bool {
        if (!root.open) return false
        root.open = false
        return true
    }

    QuickSlider {
        id: _slider
        width: parent.width
        topRadius: root.topRadius
        bottomRadius: root._optionsShown ? 0 : root.bottomRadius
        cardInset: root.cardInset
        cardLeftBleed: root.cardLeftBleed
        expanded: root.open
        reserveExpandSlot: root.reserveExpandSlot
        onGlyphClicked: root.glyphClicked()
        onExpandToggled: if (root.toggleEnabled) root.open = !root.open
        onMoved: value => root.moved(value)
    }

    CollapsibleSection {
        id: _options
        y: _slider.height
        width: parent.width
        expanded: root.open
        list: true

        Column {
            id: _optionColumn
            width: parent.width
            bottomPadding: 2

            Hairline {
                x: 14
                width: parent.width - 28
                color: Theme.menuDivider
            }
            Item { width: parent.width; height: 1 }

            Repeater {
                model: root._optionsShown ? root.options : []

                delegate: InlineOptionRow {
                    required property var modelData
                    readonly property bool active: modelData.value === root.currentValue

                    width: _optionColumn.width
                    glyph: root.glyphFor(modelData)
                    label: modelData.label
                    status: active ? "Current" : ""
                    selected: active

                    onTriggered: {
                        root.optionChosen(modelData.value)
                        root.open = false
                    }
                }
            }
        }
    }
}
