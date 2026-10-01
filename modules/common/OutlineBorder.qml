import QtQuick
import QtQuick.Shapes
import Quickshell

// uniform stroke (Rectangle.border over-weights rounded corners)
Shape {
    id: root

    property real radius: 0
    property real outlineWidth: 1
    property color outlineColor: "transparent"

    property real topLeftRadius: root.radius
    property real topRightRadius: root.radius
    property real bottomLeftRadius: root.radius
    property real bottomRightRadius: root.radius

    // the window reports the real fractional scale where the screen rounds 1.25 up to 2; whole device pixels stay crisp
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real _stroke: Math.max(1, Math.ceil(root.outlineWidth * root._dpr - 0.5)) / root._dpr

    anchors.fill: parent
    visible: outlineColor.a > 0 && outlineWidth > 0
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: root._stroke
        strokeColor: root.outlineColor
        fillColor: "transparent"
        joinStyle: ShapePath.RoundJoin
        PathRectangle {
            width: root.width
            height: root.height
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomLeftRadius: root.bottomLeftRadius
            bottomRightRadius: root.bottomRightRadius
            strokeAdjustment: root._stroke
        }
    }
}
