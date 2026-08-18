import QtQuick
import "../../../config"
import "../../../services"

// StatusActionPill, not the plain Pill BatteryWidget uses — a click here launches the
// same bluetooth-manager command BluetoothDetails already runs for its own manager row,
// gated on Bluetooth's own PATH probe for that command (same pattern NetworkWidget uses
// for the wifi editor)
StatusActionPill {
    id: root

    show: ShellSettings.barShowBluetooth && Bluetooth.available

    readonly property bool _connected: Bluetooth.connectedCount > 0
    // same three-state iconography HomePage's Bluetooth row already established: off, idle-on, actively connected
    glyph:      !Bluetooth.enabled ? "󰂲" : (_connected ? "󰂱" : "󰂯")
    // the bare rune: the family's other states only add ink around it
    glyphAlignReference: "󰂯"
    glyphAlignNudge: -1
    glyphColor: Bluetooth.enabled && _connected ? Theme.text : Theme.subtext
    textColor:  Theme.subtext
    // StatusActionPill defaults this off; this glyph switches across three states at
    // runtime (same reason NetworkWidget re-enables it), so keep the stamp transition
    animateGlyph: true
    // restores Pill's own default, which StatusActionPill trims by 1px. An optical
    // +2 bump was tried (the rune's ink is barely half as wide as its neighbors',
    // so it floats in more whitespace) and rolled back: uniform glyph size across
    // the cluster won over per-glyph optical compensation.
    glyphPixelSize: Settings.iconSize + 2
    animateText: false

    // a click only does something once the configured bluetooth-manager command is reachable
    interactive: show && Bluetooth.managerAvailable

    readonly property string _detailText: {
        if (!Bluetooth.enabled) return "Off"
        if (!_connected) return "Not connected"
        if (Bluetooth.connectedCount === 1)
            return Bluetooth.connectedName + (Bluetooth.connectedBattery >= 0
                ? " · " + Bluetooth.connectedBattery + "%" : "")
        return Bluetooth.connectedCount + " connected"
    }

    text: expanded ? _detailText : ""

    onActivated: Bluetooth.launchManager()
}
