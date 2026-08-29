pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: win

    required property ShellScreen targetScreen

    screen: targetScreen
    color: "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-bar-hint"

    readonly property bool _bottom: Metrics.barAtBottom
    readonly property real _edgeY: Metrics.popupClearanceOn(targetScreen, 4)

    implicitHeight: Math.max(Metrics.rowHeightFor(36), _hint.height + 8)
    anchors {
        top: !win._bottom
        bottom: win._bottom
        left: true
        right: true
    }
    margins.top: win._bottom ? 0 : win._edgeY
    margins.bottom: win._bottom ? win._edgeY : 0
    mask: Region {}
    visible: BarHintState.open

    Rectangle {
        id: _hint

        readonly property real _edge: 8
        readonly property real _maxW: Metrics.barHintWidthFor(
            Math.max(1, win.width - _edge * 2))
        // measured, not the label's own implicitWidth: that reads back the width set from it
        width: Math.min(_maxW, Math.ceil(_metrics.advanceWidth) + 20)
        height: Metrics.snap4Up(Math.max(Metrics.rowHeightFor(28),
            Math.ceil(_label.contentHeight) + 14))
        x: Math.round(Math.max(_edge, Math.min(
            BarHintState.anchorX - width / 2,
            win.width - width - _edge)))
        anchors.verticalCenter: parent.verticalCenter
        radius: Theme.radiusInline
        antialiasing: true
        color: Theme.menuCard

        OutlineBorder {
            radius: _hint.radius
            outlineColor: Theme.menuCardBorder
        }

        TextMetrics {
            id: _metrics
            font.family:    Settings.font
            font.pixelSize: Settings.fontCaption
            text:           BarHintState.text
        }

        ShellText {
            id: _label
            anchors.centerIn: parent
            width: _hint.width - 16
            text: BarHintState.text
            color: Theme.withAlpha(Theme.text, 0.82)
            font.pixelSize: Settings.fontCaption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }
}
