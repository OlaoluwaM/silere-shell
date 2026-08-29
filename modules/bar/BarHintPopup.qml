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

    readonly property bool _shown: BarHintState.open
    property real _op:    0
    property real _rise:  0
    property bool _ready: false

    function _hiddenRise(): real {
        return win._bottom ? Motion.popEdgeOffset : -Motion.popEdgeOffset
    }

    function _settle(): void {
        _enter.stop()
        _exit.stop()
        win._op = win._shown ? 1.0 : 0.0
        win._rise = win._shown ? 0.0 : win._hiddenRise()
    }

    on_ShownChanged: {
        if (!win._ready) return
        if (ShellSettings.reduceMotion) {
            win._settle()
        } else if (win._shown) {
            _exit.stop()
            _enter.restart()
        } else {
            _enter.stop()
            _exit.restart()
        }
    }

    Component.onCompleted: {
        win._rise = win._hiddenRise()
        if (ShellSettings.reduceMotion) {
            win._ready = true
            win._settle()
        } else {
            _startupFrame.start()
        }
    }

    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (!ShellSettings.reduceMotion) return
            _startupFrame.stop()
            win._ready = true
            win._settle()
        }
    }

    // the window is built the moment the hint is wanted; starting its entrance in
    // onCompleted makes construction and the first animated frame compete on the GUI thread
    FrameAnimation {
        id: _startupFrame
        running: false
        onTriggered: {
            stop()
            win._ready = true
            if (win._shown) _enter.restart()
            else win._settle()
        }
    }

    ParallelAnimation {
        id: _enter
        NumberAnimation { target: win; property: "_op";   to: 1.0; duration: Motion.popInFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardDecel }
        NumberAnimation { target: win; property: "_rise"; to: 0.0; duration: Motion.popIn;     easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
    }

    ParallelAnimation {
        id: _exit
        NumberAnimation { target: win; property: "_op";   to: 0.0;                duration: Motion.popOutFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccel }
        NumberAnimation { target: win; property: "_rise"; to: win._hiddenRise();  duration: Motion.popOut;     easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
    }

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
        opacity: win._op
        visible: win._op > 0.001
        transform: Translate { y: win._rise }

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
