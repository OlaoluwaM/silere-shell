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
    // armed setting through select -- currentMinutes stays the single armed source
    property string customKey: ""
    property color accentColor: Theme.accent

    signal select(int minutes)

    readonly property var _presets: Durations.sanitizePresets(root.presetsValue)
    // "Custom" is derived, never stored: an armed value outside the packaged list
    // is what custom means, so the chip row can never disagree with the setting
    // about which mode it is in
    readonly property bool _customActive: root._presets.indexOf(root.currentMinutes) < 0
    // ephemeral, not persisted: keeps the slider from collapsing out from under a
    // drag that happens to cross a listed preset value (the matching chip still
    // lights up as honest feedback)
    property bool _customEngaged: false

    ChoiceChipRow {
        width: parent.width
        glyph: "󰥔"
        label: "Duration"
        accentColor: root.accentColor
        currentValue: root._customActive ? -1 : root.currentMinutes
        model: {
            const out = []
            for (let i = 0; i < root._presets.length; i++) {
                const p = root._presets[i]
                if (p > 0) out.push({ value: p, label: Durations.label(p) })
            }
            // custom sits ahead of "until turned off" so the two open-ended
            // choices bracket the fixed presets
            out.push({ value: -1, label: "Custom" })
            out.push({ value: 0, label: Durations.label(0) })
            return out
        }
        onChosen: (v) => {
            if (v === -1) {
                root._customEngaged = true
                root.select(ShellSettings[root.customKey])
            } else {
                root._customEngaged = false
                root.select(v)
            }
        }
    }

    SliderRow {
        width: parent.width
        visible: root._customEngaged || root._customActive
        label: "Custom duration"
        key: root.customKey
        step: 5
        displayValue: Durations.label(Math.round(value))
        // mid-run drags re-arm from now, the same replace-the-stop semantics
        // the chips have
        onChanged: (v) => root.select(Math.round(v))
    }
}
