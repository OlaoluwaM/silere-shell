import QtQuick
import "../../../config"
import "../../common"

// The collapsing 18 px icon cell a settings row leads with: it takes no width when its
// glyph is empty, so the label beside it can anchor to its right edge without a spacer.
// Rows whose cell keeps its width regardless (ToggleRow, SelectRow) draw their own.
ShellText {
    horizontalAlignment: Text.AlignHCenter
    visible: text.length > 0
    width: visible ? 18 : 0
    color: Theme.withAlpha(Theme.subtext, 0.85)
    font.pixelSize: Settings.iconSize + 2
}
