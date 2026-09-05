import QtQuick
import "../../../services"

// Third of the self-set session modes after caffeine and dnd: it rides the same
// StatusActionPill and shares the connectivity cluster's meta group, sitting
// beside the radio pills it silences. "Airplane on" is derived, not stored --
// QuickActionsState reads it as every controllable radio being off, so radios
// cut individually light this too, and that is the service's deliberate model.
StatusActionPill {
    id: root

    show: QuickActionsState.airplaneAvailable && !QuickActionsState.radiosOn
    hintText: root.interactive ? "Click turn off airplane mode" : ""

    // the pill's own text is empty until hover-expanded, which a screen reader never does
    accessibleName: "Airplane mode on"
    glyph: "󰀝"
    // single-state widget, so the reference is the glyph itself
    glyphAlignReference: "󰀝"

    text: !expanded ? "" : "Airplane Mode"

    // a click always brings the radios back -- the fastest way out, same as the
    // dnd pill's always-clears policy; the latch restores only what was on
    onActivated: QuickActionsState.toggleAirplane()
}
