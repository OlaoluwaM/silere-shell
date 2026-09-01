import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "BAR"; first: true }
    SettingsCard {
        ChoiceChipRow {
            glyph: "󰍹"; label: "Position"
            currentValue: ShellSettings.barPosition
            model: [
                { value: "top",    label: "Top"    },
                { value: "bottom", label: "Bottom" }
            ]
            onChosen: (v) => ShellSettings.barPosition = v
        }
        ChoiceChipRow {
            glyph: "󰲏"; label: "Height"
            currentValue: ShellSettings.barHeight
            model: [
                { value: 28, label: "Compact" },
                { value: 36, label: "Normal"  },
                { value: 44, label: "Tall"    }
            ]
            onChosen: (v) => ShellSettings.barHeight = v
        }
        // docked pins the bar's own corners to zero; the hover capsule and OSD pill still take
        // this radius, and they round at half a row rather than half the bar
        SliderRow {
            glyph: "󱓻"
            label: ShellSettings.barFloating ? "Roundness" : "Highlight roundness"
            key: "barRadius"
            displayValue: ShellSettings.barRadius === 0 ? "Flat"
                : ShellSettings.barRadius >= (ShellSettings.barFloating
                    ? ShellSettings.barHeight / 2 : Metrics.barRowHeight / 2) ? "Round"
                : ShellSettings.barRadius + "px"
        }
        SliderRow {
            glyph: "󰗌"; label: "Opacity"
            key: "barOpacity"
            step: 0.02
            displayValue: Math.round(Theme.panelOpacity * 100) + "%"
        }
        ToggleRow {
            glyph: "󱡓"; label: "Popups match bar opacity"
            description: "Notifications, calendar, tray and quick actions"
            key: "popupMatchBarOpacity"
        }
    }

    SectionLabel { label: "GLASS" }
    SettingsCard {
        ToggleRow {
            glyph: "󰂵"; label: "Glass surfaces"
            description: "Frost popups with the wallpaper tint"
            key: "glassSurfaces"
        }
        SliderRow {
            glyph: "󰗌"; label: "Opacity"
            key: "glassOpacity"
            step: 0.02
            enabled: ShellSettings.glassSurfaces
            displayValue: Math.round(ShellSettings.glassOpacity * 100) + "%"
        }
    }

    SectionLabel { label: "FLOATING" }
    SettingsCard {
        ToggleRow {
            glyph: "󰖲"; label: "Floating bar"
            key: "barFloating"
        }
        // one disclosure for one toggle: two gated on the same flag played two reveals
        CollapsibleSection {
            expanded: ShellSettings.barFloating
            ToggleRow {
                glyph: "󰡌"; label: "Fit window gaps"
                description: "Align to Hyprland's gaps_out, not a fraction"
                key: "barFitGaps"
            }
            // width only means something once fit-gaps is off; it's the fraction that mode replaces
            CollapsibleSection {
                expanded: !ShellSettings.barFitGaps
                SliderRow {
                    glyph: "󰡎"; label: "Width"
                    key: "barWidth"
                    step: 0.02
                    displayValue: Math.round(ShellSettings.barWidth * 100) + "%"
                }
            }
            // stepped in 4s: the bar edge has to stay on the 4px grid or hairlines straddle a physical pixel
            SliderRow {
                glyph: "󰡏"; label: "Edge gap"
                key: "barGap"
                step: 4
                displayValue: ShellSettings.barGap === 0 ? "None" : ShellSettings.barGap + "px"
            }
        }
    }
}
