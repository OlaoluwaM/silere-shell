import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: root

    readonly property bool show: ShellSettings.barShowBluetooth && Bluetooth.available
    readonly property bool layoutVisible: show || opacity > 0.001
    readonly property bool _linked: Bluetooth.enabled && Bluetooth.connectedCount > 0
    readonly property int  _battery: _linked ? Bluetooth.connectedBattery : -1

    readonly property string _detailText: {
        if (!Bluetooth.enabled) return "Off"
        if (!root._linked) return "Not connected"
        if (Bluetooth.connectedCount > 1)
            return Bluetooth.connectedCount + " devices"
        return root._battery >= 0
            ? Bluetooth.connectedName + " " + root._battery + "%"
            : Bluetooth.connectedName
    }

    collapsed: !show
    visible:   layoutVisible
    opacity:   !show ? 0.0 : Bluetooth.enabled ? 1.0 : 0.45
    MotionBehavior on opacity {
        NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic }
    }

    glyph: !Bluetooth.enabled ? "󰂲"
        : root._linked && Bluetooth.connectedCount === 1 && Bluetooth.connectedGlyph.length > 0
            ? Bluetooth.connectedGlyph : "󰂯"
    glyphColor: root._linked ? Theme.text : Theme.subtext
    textColor:  Theme.subtext
    animateText: false
    maxTextWidth: compact ? 130 : 220

    text: expanded ? root._detailText : ""
    accessibleName: "Bluetooth, " + root._detailText
}
