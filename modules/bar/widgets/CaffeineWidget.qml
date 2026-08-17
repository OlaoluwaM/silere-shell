import QtQuick
import "../../../services"

// StatusActionPill, not the plain Pill BatteryWidget uses — that one is display-only,
// but this pill is also the fastest way to flip the manual unit off, so it needs the
// click wiring StatusActionPill already gives UpdatesWidget/BluetoothWidget. `show`
// still drives the same fade the other pills use; StatusActionPill just owns it here.
StatusActionPill {
    id: root

    show: ShellSettings.barShowCaffeine && Caffeine.available && Caffeine.inhibited

    glyph: "󰅶"
    // single-state widget, so the reference is the glyph itself
    glyphAlignReference: "󰅶"

    text: expanded ? (Caffeine.manualActive ? "Caffeine" : Caffeine.inhibitorLabel) : ""

    onActivated: Caffeine.toggle()
}
