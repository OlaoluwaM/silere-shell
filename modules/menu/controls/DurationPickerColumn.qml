import QtQuick
import "../../../config"
import "../../../services"

// The duration picker the caffeine and DND rows share: preset chips bracketed by
// Custom and "Until turned off", with a schema-bounded slider while Custom is in
// play. One control instead of two copies for the same reason the sanitizer and
// labels live in Durations -- the two pickers must never drift apart.
Column {
    id: root

    // the packaged comma-separated preset list, sanitized here
    property string presetsValue: ""
    // the armed duration this picker reflects
    property int currentMinutes: 0
    // settings key remembering the custom slider's position; the slider derives its
    // bounds from this key's schema, and picking Custom copies its value into the
    // armed setting through chosen -- currentMinutes stays the single armed source
    property string customKey: ""
    property color accentColor: Theme.accent

    readonly property var _presets: Durations.sanitizePresets(root.presetsValue)
    readonly property var _timedPresets: root._presets.filter(p => p > 0)
    // "Custom" is derived, never stored: an armed value outside the packaged list
    // is what custom means, so the chip row can never disagree with the setting
    // about which mode it is in
    readonly property bool _customActive: root._presets.indexOf(root.currentMinutes) < 0
    // ephemeral, not persisted: keeps the slider from collapsing out from under a
    // drag that happens to cross a listed preset value (the matching chip still
    // lights up as honest feedback). Also armed by the slider's own onChanged,
    // since the InlinePicker Loader can recreate this column with a custom value
    // already active -- interacting with the slider pins it open no matter which
    // path made it visible
    property bool _customEngaged: false

    signal chosen(int minutes)

    // two rows, split by meaning rather than line length: the finite packaged
    // presets ride the labelled row, and the two open-ended choices below never
    // move -- so a longer preset list grows the top row instead of reshuffling
    // everything, and no cell ever gets squeezed into eliding its label
    ChoiceChipRow {
        width: parent.width
        visible: root._timedPresets.length > 0
        glyph: "󰥔"
        label: "Duration"
        accentColor: root.accentColor
        // -2 is "no chip here": while Custom or Unlimited is armed, this row
        // stays entirely unlit and the mode row below carries the selection
        currentValue: root._customActive || root.currentMinutes === 0
            ? -2 : root.currentMinutes
        model: root._timedPresets.map(p => ({ value: p, label: Durations.label(p) }))
        onChosen: (v) => {
            root._customEngaged = false
            root.chosen(v)
        }
    }

    ChoiceChipRow {
        width: parent.width
        accentColor: root.accentColor
        currentValue: root._customActive ? -1
            : root.currentMinutes === 0 ? 0 : -2
        model: [
            { value: -1, label: "Custom" },
            { value: 0, label: Durations.label(0) }
        ]
        onChosen: (v) => {
            if (v === -1) {
                root._customEngaged = true
                root.chosen(ShellSettings[root.customKey])
            } else {
                root._customEngaged = false
                root.chosen(v)
            }
        }
    }

    SliderRow {
        width: parent.width
        visible: root._customEngaged || root._customActive
        label: "Custom duration"
        key: root.customKey
        step: 5
        // commits once on release rather than per crossed step -- caffeine's
        // commit runs a 3-process systemd chain, and a drag shouldn't spawn it
        // a dozen times. displayValue tracks shownValue (the live, uncommitted
        // position) instead of value so the label still follows the finger
        commitOnRelease: true
        displayValue: Durations.label(Math.round(shownValue))
        // mid-run drags re-arm from now, the same replace-the-stop semantics
        // the chips have
        onChanged: (v) => {
            root._customEngaged = true
            root.chosen(Math.round(v))
        }
    }
}
