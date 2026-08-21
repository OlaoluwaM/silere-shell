import QtQuick
import "../../../services"

// Caffeine's sibling: another self-set session mode that deserves a standing
// reminder while it is on, so it rides the same StatusActionPill and shares the
// connectivity cluster's meta group as a visual statement, exactly as caffeine does.
StatusActionPill {
    id: root

    // effectiveDnd, not dnd: scheduled quiet hours silence notifications just as
    // thoroughly as the manual switch, and a silenced session with no reminder is
    // the gap this pill exists to close. Fullscreen auto-silence stays out — that
    // state is transient and nobody chose it, so a pill for it would only flicker.
    show: Notifications.effectiveDnd

    glyph: "󰂛"
    // single-state widget, so the reference is the glyph itself
    glyphAlignReference: "󰂛"

    text: expanded ? (Notifications.dnd ? "Do Not Disturb" : "Quiet hours") : ""

    // only the manual switch is click-clearable: with quiet hours alone active,
    // toggling would flip manual DND on underneath the schedule — an invisible
    // change now and a surprise still-lit pill after the quiet window ends
    interactive: show && Notifications.dnd
    onActivated: Notifications.toggleDnd()
}
