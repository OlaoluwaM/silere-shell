import QtQuick
import "../../../config"
import "../../../services"

// Caffeine's sibling: another self-set session mode that deserves a standing
// reminder while it is on, so it rides the same StatusActionPill and shares the
// connectivity cluster's meta group as a visual statement, exactly as caffeine does.
// Fullscreen auto-silence deliberately never lights this — that state is transient
// and nobody chose it, so a pill for it would only flicker.
StatusActionPill {
    id: root

    show: Notifications.dnd

    // the pill's own text is empty until hover-expanded, which a screen reader never does
    accessibleName: Notifications.dndRemainingMinutes >= 0
        ? "Do Not Disturb, " + Durations.label(Notifications.dndRemainingMinutes) + " left"
        : "Do Not Disturb on"
    glyph: "󰂛"
    // single-state widget, so the reference is the glyph itself
    glyphAlignReference: "󰂛"

    text: !expanded ? ""
        : Notifications.dndRemainingMinutes >= 0
            ? Durations.label(Notifications.dndRemainingMinutes) + " left"
        : "Do Not Disturb"

    // a click always ends the run, timed or not — the fastest way out, same as
    // caffeine; StatusActionPill's own show-gated interactive default applies
    onActivated: Notifications.toggleDnd()
}
