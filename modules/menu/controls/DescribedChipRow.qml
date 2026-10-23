import QtQuick
import "../../../config"
import "../../common"

// A chip row with a subtitle under its title. It wraps upstream's ChoiceChipRow instead
// of changing it, since upstream reworks that file often, and uses only its public
// surface: given no label or glyph, the base draws just its chips across the width it is
// handed, so this row sizes that width and draws the glyph and text as ToggleRow does.
MenuRow {
    id: root

    property string title:       ""
    property string description: ""
    property var    model:       []
    property var    currentValue

    signal chosen(var value)

    rowHovered:     _hover.hovered
    rowInteractive: root.enabled

    readonly property int _descPadV: 11
    // the glyph cell and its gap, or the bare inset without one, as in SelectRow
    readonly property int _leadW: root.glyph.length > 0 ? 14 + 18 + 10 : 14
    height: root.description.length > 0
        ? 4 * Math.ceil((root._descPadV * 2 + _textCol.implicitHeight) / 4)
        : Metrics.rowHeightFor(44)

    // chip cells sized as ChoiceChipRow sizes its own, so these match every other chip row
    FontMetrics {
        id: _chipFm
        font.family: Settings.font
        font.pixelSize: Settings.fontLabel
        font.weight: Font.DemiBold
    }
    readonly property real _chipsW: {
        // advanceWidth() is a call, so it registers no dependency; reading the font does
        void _chipFm.font.pixelSize
        let widest = 0
        for (const o of root.model) {
            const glyphW = o.glyph !== undefined && o.glyph !== null && String(o.glyph).length > 0 ? 18 : 0
            widest = Math.max(widest, _chipFm.advanceWidth(String(o.label ?? "")) + glyphW)
        }
        const n = Math.max(1, root.model.length)
        return n * Math.max(44, Math.ceil(widest) + 22) + (n - 1) * 5
    }

    Accessible.name: root.title
    Accessible.description: root.description

    HoverHandler { id: _hover; enabled: root.enabled }

    RowGlyph {
        id: _glyph
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        color: Theme.withAlpha(Theme.subtext, 0.82)
        opacity: root.enabled ? 1.0 : Theme.disabledOpacity
    }

    Column {
        id: _textCol
        anchors.left: _glyph.right
        anchors.leftMargin: root.glyph.length > 0 ? 10 : 0
        anchors.right: _chips.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        opacity: root.enabled ? 1.0 : Theme.disabledOpacity

        ShellText {
            width: parent.width
            text: root.title
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.text, 0.88)
            font.pixelSize: Settings.fontSize
        }

        ShellText {
            visible: root.description.length > 0
            width: parent.width
            text: root.description
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: Theme.menuTextDetail
            font.pixelSize: Settings.fontCaption
            lineHeight: 1.1
        }
    }

    ChoiceChipRow {
        id: _chips
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        // The base keeps 28 px of margin around chips it draws headless, 12 px of it on the
        // right. The text keeps 96 px the way SelectRow's label does; past that the chips
        // share what is left down to 44 px each, their labels shrinking and then eliding.
        width: Math.min(root._chipsW + 28, Math.max(
            root.model.length * 44 + (root.model.length - 1) * 5 + 28,
            root.width - root._leadW - 96))
        // this row paints the hover once across the whole width
        rowInteractive: false
        model: root.model
        currentValue: root.currentValue
        onChosen: (value) => root.chosen(value)
    }
}
