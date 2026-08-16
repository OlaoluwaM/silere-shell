import QtQuick
import "../../../config"
import "../../common"

// a plain read-only label:value line for status panels (connected Wi-Fi details,
// and any future device-details surface) — no hover state, nothing to tap
Item {
    id: root

    property string label: ""
    property string value: ""

    readonly property int rowHeight: Metrics.rowHeightFor(26)
    width: parent ? parent.width : 0
    implicitHeight: rowHeight
    height: implicitHeight

    ShellText {
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.right: _value.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        elide: Text.ElideRight
        color: Theme.withAlpha(Theme.subtext, 0.60)
        font.pixelSize: Settings.fontCaption
    }

    ShellText {
        id: _value
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0, root.width * 0.62))
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: root.value
        color: Theme.withAlpha(Theme.text, 0.86)
        font.pixelSize: Settings.fontLabel
        font.weight: Font.Medium
    }
}
