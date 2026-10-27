import QtQuick
import "../../config"
import "../../services"
import "../common"

// The battery in the lock's top-right corner: glyph and percentage, a word when it is
// charging or needs the charger. The item's top edge is where the digits' ink starts, so
// the row lines up with the clock's ink whatever either font's line box does.
Item {
    id: root

    // off on the outputs that show the clock alone
    property bool wanted: true
    readonly property string family: LockState.fontFamily
    readonly property int textSize: LockState.px(14)
    // the glyph runs a size up, as the mockup's icon does beside its 14px text
    readonly property int glyphSize: LockState.px(16)
    readonly property real _k: root.textSize / 1000
    readonly property real _glyphK: root.glyphSize / 1000

    readonly property bool _charging: Battery.charging && !Battery.full
    readonly property color _tone: Battery.low ? Theme.error : Theme.withAlpha(Theme.text, 0.88)

    implicitWidth: _row.width
    implicitHeight: -_digitsInk.tightBoundingRect.y * root._k
    // UPower reads 0 until it has a reading; a bare "%" would be worse than nothing
    visible: root.wanted && Battery.available && Battery.label.length > 0
    opacity: LockState.fontReady ? 1 : 0
    MotionBehavior on opacity { NumberAnimation { duration: Motion.slow } }

    Accessible.role: Accessible.StaticText
    Accessible.name: "Battery " + _label.text

    TextMetrics {
        id: _digitsInk
        font.family: root.family
        font.pixelSize: 1000
        font.features: { "tnum": 1 }
        text: "0123456789"
    }
    // the glyph centres on the digits' ink rather than on a line box: the symbols fallback
    // lends it a taller line with a lower baseline
    TextMetrics {
        id: _glyphInk
        font.family: _glyph.font.family
        font.pixelSize: 1000
        text: _glyph.text
    }

    Row {
        id: _row
        spacing: LockState.px(8)

        ShellText {
            id: _glyph
            y: _label.y + _label.baselineOffset
                + (_digitsInk.tightBoundingRect.y + _digitsInk.tightBoundingRect.height / 2) * root._k
                - _glyph.baselineOffset
                - (_glyphInk.tightBoundingRect.y + _glyphInk.tightBoundingRect.height / 2) * root._glyphK
            text: Battery.icon
            color: root._tone
            font.pixelSize: root.glyphSize
        }

        ShellText {
            id: _label
            y: -_digitsInk.tightBoundingRect.y * root._k - _label.baselineOffset
            text: Battery.label + (Battery.low ? " · plug in" : root._charging ? " · charging" : "")
            color: root._tone
            font.family: root.family
            font.pixelSize: root.textSize
            font.features: { "tnum": 1 }
        }
    }
}
