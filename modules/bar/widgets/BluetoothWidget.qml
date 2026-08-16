import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property bool show: ShellSettings.barShowBluetooth && Bluetooth.available
    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001
    collapsed: !show

    readonly property bool _connected: Bluetooth.connectedCount > 0
    // same three-state iconography HomePage's Bluetooth row already established: off, idle-on, actively connected
    glyph:      !Bluetooth.enabled ? "󰂲" : (_connected ? "󰂱" : "󰂯")
    glyphColor: Bluetooth.enabled && _connected ? Theme.text : Theme.subtext
    textColor:  Theme.subtext
    animateText: false

    opacity: _baseOpacity
    visible: layoutVisible

    MotionBehavior on _baseOpacity {
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }

    readonly property string _detailText: {
        if (!Bluetooth.enabled) return "Off"
        if (!_connected) return "Not connected"
        if (Bluetooth.connectedCount === 1)
            return Bluetooth.connectedName + (Bluetooth.connectedBattery >= 0
                ? " · " + Bluetooth.connectedBattery + "%" : "")
        return Bluetooth.connectedCount + " connected"
    }

    text: expanded ? _detailText : ""
}
