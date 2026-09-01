import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Pill {
    id: batteryPill

    // an over-limit charge is worth surfacing even while auto-hide would otherwise
    // fold the pill away on AC -- it's the one charging state that isn't "normal"
    readonly property bool overChargeLimit: Battery.chargeLimit > 0 && Battery.pct > Battery.chargeLimit
    readonly property bool autoHidden: ShellSettings.batteryAutoHide && (Battery.charging || Battery.full)
        && !overChargeLimit
    readonly property bool show: ShellSettings.barShowBattery && Battery.available && !autoHidden
    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001
    collapsed: !show

    readonly property color _iconColor: overChargeLimit ? Theme.warning : Battery.iconColor

    glyph:          Battery.icon
    accessibleName: {
        if (!Battery.available) return "Battery"
        const parts = []
        if (Battery.label.length > 0)       parts.push(Battery.label)
        if (Battery.statusLabel.length > 0) parts.push(Battery.statusLabel)
        return parts.length > 0 ? "Battery " + parts.join(", ") : "Battery"
    }
    // full battery: every level and charging variant shares its outline
    glyphAlignReference: "󰁹"
    glyphAlignNudge: -1
    // no size override: the whole status cluster renders at StatusActionPill's
    // baseline. The old +3 bump made this the largest ink in the row (battery
    // glyphs are tall, 0.84x vs the tray grid's 0.68x); the cluster was
    // normalized down to its smallest member rather than bumping the rest up.
    glyphColor:     _iconColor
    textColor:      _iconColor
    animateGlyph:   false
    shrinkDelay:    0
    reserveText:    "100%"
    levelValue:     Battery.pct > 0 ? Battery.pct / 100 : -1
    levelVisible:   Battery.pct > 0 && ShellSettings.valuesOnHover
                    && ShellSettings.hoverLevelBar && !expanded
    levelColor:     _iconColor
    opacity: _baseOpacity * (Battery.critical ? 1.0 - Battery.alertPulse * 0.60
                           : (Battery.low     ? 1.0 - Battery.alertPulse * 0.18 : 1.0))
    visible: layoutVisible

    MotionBehavior on _baseOpacity {NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    text: {
        if (ShellSettings.valuesOnHover && !expanded)
            return ""
        if (!expanded)
            return Battery.label

        // no statusLabel fallback: with auto-hide on, the pill only exists while
        // discharging, so naming the state next to the percentage says nothing
        const detail = Battery.timeLabel
        if (Battery.label.length === 0)
            return detail
        if (detail.length > 0)
            return Battery.label + " · " + detail
        return Battery.label
    }
}
