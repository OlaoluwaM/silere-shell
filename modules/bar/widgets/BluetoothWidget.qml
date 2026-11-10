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
    // no size override: the status cluster keeps one glyph size, StatusActionPill's
    // baseline, rather than optical bumps per glyph such as one for the rune's narrow ink
    animateText: false

    // a click only does something once the configured bluetooth-manager command is reachable
    interactive: show && Bluetooth.managerAvailable
    hintText: interactive ? "Open Bluetooth manager" : ""

    text: expanded ? Bluetooth.statusText : ""
    accessibleName: "Bluetooth, " + Bluetooth.statusText

    onActivated: Bluetooth.launchManager()
}
