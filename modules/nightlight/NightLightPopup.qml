pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../common"
import "../menu/controls"

// The shell's own interface over sunsetr: the daemon owns the screen's colour temperature
// and this card only shows it and writes its config. The menu's Night Light row opens it
// in the menu's place. Built like modules/mediapopup/MediaPopup.qml (an OverlayPopupWindow
// around FloatingPopupCard chrome), with the menu's own rows as the payload.
OverlayPopupWindow {
    id: win

    required property ShellScreen targetScreen

    screen: targetScreen
    popupState: NightLightPopupState
    layerNamespace: "silere-nightlight"
    popupCard: card

    FloatingPopupCard {
        id: card
        win: win
        open: NightLightPopupState.open
        anchorX: NightLightPopupState.effectiveAnchorX
        barBottom: Metrics.barAtBottom
        swapIn: NightLightPopupState.fromMenu

        // the media card's width, so the two cards that hang off the bar match
        readonly property int cardWidth: 330
        // roomier than the 6 the list popups use: these rows carry sliders and an arc, which read
        // cramped that close to the edge
        readonly property int pad: 12
        // sunsetr's settings can be changed only while the tool is there and its config has been read
        readonly property bool editable: NightLight.available && NightLight.configKnown

        width:  cardWidth
        height: _body.height + 2 * pad

        Connections {
            target: NightLightPopupState
            function onOpenChanged() { if (NightLightPopupState.open) card.forceActiveFocus() }
        }
        Component.onCompleted: if (NightLightPopupState.open) card.forceActiveFocus()

        // sunsetr's limits for its own config, not a settings key's range; the two clock rows
        // share one range and one grid
        readonly property int tempMin: 1000
        readonly property int tempMax: 6500
        readonly property int tempStep: 100
        readonly property int minuteMin: 0
        readonly property int minuteMax: 1425
        readonly property int minuteStep: 15

        // minutes of the day as the clock reads them, so the sliders follow the 12h/24h setting
        function _clockLabel(min: int): string {
            return DateTime.clockText(new Date(2000, 0, 1, Math.floor(min / 60), min % 60))
        }

        SettingsCard {
            id: _body
            x: card.pad
            y: card.pad
            width: card.cardWidth - 2 * card.pad
            // the popup is the only surface; the rows' end corners stay concentric with its own
            plain: true
            radius: Math.max(0, card.radius - card.pad)

            ControlRow {
                glyph: NightLight.enabled ? "󰖔" : "󰖙"
                label: "Night Light"
                active: NightLight.enabled
                status: NightLight.lastError.length > 0 ? NightLight.lastError : NightLight.detailLabel
                accentColor: NightLight.lastError.length > 0 ? Theme.error : Theme.accent
                statusColor: NightLight.lastError.length > 0 ? Theme.error : "transparent"
                showSwitch: true
                // the card can be opened by a keybind on a machine without the tool
                available: NightLight.available
                onActivated: NightLight.toggle()
            }

            // held through the card's exit, or the arc would blank while its labels still fade
            SunArc { shown: NightLightPopupState.open || card.opacity > 0 }

            SliderRow {
                // a fixed temperature is another key of sunsetr's, which ignores this one until a schedule is picked
                enabled: card.editable && NightLight.schedule !== "fixed"
                glyph: "󰔄"
                label: "Night temperature"
                // blank until read: the value before that is a placeholder, not sunsetr's
                displayValue: NightLight.configKnown ? NightLight.nightTemp + "K" : ""
                value: NightLight.nightTemp
                min: card.tempMin; max: card.tempMax; step: card.tempStep
                onChanged: (v) => NightLight.setNightTemp(v)
            }

            ChoiceChipRow {
                enabled: card.editable
                glyph: "󰥔"
                label: "Schedule"
                model: [
                    { label: "Sun",   value: "sun" },
                    { label: "Clock", value: "clock" }
                ]
                currentValue: NightLight.configKnown ? NightLight.schedule : ""
                onChosen: (v) => NightLight.setSchedule(v)
            }

            // every part of the swap is symmetric so the card's height moves one way; none is open
            // until the config is read, when the schedule is still a placeholder, or once the tool is gone
            CollapsibleSection {
                expanded: card.editable && NightLight.schedule === "clock"
                symmetric: true

                SliderRow {
                    enabled: card.editable
                    glyph: "󰖛"
                    label: "Sunset"
                    displayValue: card._clockLabel(NightLight.clockSunsetMin)
                    value: NightLight.clockSunsetMin
                    min: card.minuteMin; max: card.minuteMax; step: card.minuteStep
                    onChanged: (v) => NightLight.setClockSunset(v)
                }
                SliderRow {
                    enabled: card.editable
                    glyph: "󰖜"
                    label: "Sunrise"
                    displayValue: card._clockLabel(NightLight.clockSunriseMin)
                    value: NightLight.clockSunriseMin
                    min: card.minuteMin; max: card.minuteMax; step: card.minuteStep
                    onChanged: (v) => NightLight.setClockSunrise(v)
                }
            }
            CollapsibleSection {
                expanded: card.editable && NightLight.schedule === "sun"
                symmetric: true

                HintText { text: "Follows the sun at " + NightLight.locationLabel + "." }
            }
            // reached only by editing sunsetr's config by hand; either choice above leaves it
            CollapsibleSection {
                expanded: card.editable && NightLight.schedule === "fixed"
                symmetric: true

                HintText { text: "Held at one fixed temperature. Pick a schedule to change that." }
            }

            // one section per reason, so neither sentence changes while it folds away
            CollapsibleSection {
                expanded: !NightLight.available

                HintText { text: "Night Light needs sunsetr." }
            }
            CollapsibleSection {
                expanded: NightLight.available && !NightLight.configKnown

                // sunsetr writes its config on its first start; one it cannot give while running is unreadable
                HintText {
                    text: NightLight.live ? "sunsetr's settings could not be read."
                        : "Settings unlock after Night Light has run once."
                }
            }
        }
    }
}
