import QtQuick
import Quickshell

// whole device pixels from the window's own ratio: the screen's rounded ratio reads 2 at a 1.25 output
// scale, which made 1/dpr 0.625 of a real pixel that survives or vanishes on sub-pixel phase alone
Rectangle {
    property bool vertical: false

    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real thickness: Math.max(1, Math.ceil(_dpr - 0.5)) / _dpr

    implicitWidth: vertical ? thickness : 0
    implicitHeight: vertical ? 0 : thickness
    antialiasing: false
}
