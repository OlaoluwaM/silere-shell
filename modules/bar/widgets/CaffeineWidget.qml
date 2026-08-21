import QtQuick
import "../../../config"
import "../../../services"

// StatusActionPill, not the plain Pill BatteryWidget uses — that one is display-only,
// but this pill is also the fastest way to flip the manual unit off, so it needs the
// click wiring StatusActionPill already gives UpdatesWidget/BluetoothWidget. `show`
// still drives the same fade the other pills use; StatusActionPill just owns it here.
StatusActionPill {
    id: root

    // inhibited alone would wait out the 15s systemd-inhibit --list poll before a
    // manual toggle (click or the Super+C IPC chord) lit the pill; manualActive
    // flips the moment toggle() runs, so pairing it in here makes the pill track
    // our own runs optimistically. The poll still matters on its own — it is the
    // only way to see idle blocked by something other than this unit, and logind
    // offers no change signal to push that instead.
    show: ShellSettings.barShowCaffeine && Caffeine.available
        && (Caffeine.inhibited || Caffeine.manualActive)

    glyph: "󰅶"
    // single-state widget, so the reference is the glyph itself
    glyphAlignReference: "󰅶"

    // a timed run's hover label is its countdown, same as the DND pill's; an
    // untimed run keeps the plain name, and a foreign inhibitor keeps its own
    text: !expanded ? ""
        : Caffeine.manualActive
            ? (Caffeine.remainingMinutes >= 0
                ? Durations.label(Caffeine.remainingMinutes) + " left"
                : "Caffeine")
        : Caffeine.inhibitorLabel

    // the countdown rides a 15s/120s poll, so ask for a fresh readout the moment
    // the hover label expands into view instead of showing up to that much staleness
    onExpandedChanged: if (expanded && Caffeine.manualActive) Caffeine.refreshRemaining()

    onActivated: Caffeine.toggle()
}
