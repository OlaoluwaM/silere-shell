import QtQuick
import "../../config"
import "../common"

// The lock's clock and date. Placed by ink, not by line boxes: the item's top edge is where
// the clock's digits start, whatever the family; across, the clock keeps its pen origin on
// the left edge as the mockup does, and the date follows its ink. Qt sets a line's
// first baseline at the font's ascent and lets lineHeight below 1 shrink the box from the
// top, so the mockup's CSS line maths does not carry over; every offset below is read from
// the glyphs themselves at run time instead of from a table per font.
Item {
    id: root

    property bool showDate: true
    readonly property string family: LockState.fontFamily

    readonly property int clockSize: LockState.px(148)
    readonly property int dateSize: LockState.px(20)
    // the mockup's 18px between line boxes, as JetBrains Mono's ink lands: the date's
    // capitals start this far under the clock's baseline
    readonly property int dateGap: LockState.px(37)

    // Ink is measured at 1000px and scaled down: tightBoundingRect rounds out to whole
    // pixels, which at the clock's size would be most of the 1px the alignment allows
    readonly property real _clockK: root.clockSize / 1000
    readonly property real _dateK: root.dateSize / 1000
    // the tallest digit, so the clock's top edge holds still from one minute to the next
    readonly property real digitHeight: -_digitsInk.tightBoundingRect.y * root._clockK

    // from the top of the digits' ink, so a parent that lays this out sees what draws
    implicitWidth: _clock.implicitWidth
    implicitHeight: root.showDate ? _date.y + _date.implicitHeight : root.digitHeight

    // not until the face is settled, so the clock never draws in one font and jumps to another
    opacity: LockState.fontReady ? 1 : 0
    MotionBehavior on opacity { NumberAnimation { duration: Motion.slow } }

    TextMetrics {
        id: _digitsInk
        font: _clockMeasure.font
        text: "0123456789"
    }
    TextMetrics {
        id: _clockLead
        font: _clockMeasure.font
        text: _clock.text.charAt(0)
    }
    TextMetrics {
        id: _dateLead
        font.family: root.family
        font.pixelSize: 1000
        text: _date.text.charAt(0)
    }
    TextMetrics {
        id: _dateCap
        font.family: root.family
        font.pixelSize: 1000
        text: "H"
    }
    // the clock's face at the measuring size, shared by both clock measurements
    TextMetrics {
        id: _clockMeasure
        font.family: root.family
        font.weight: Font.ExtraLight
        font.pixelSize: 1000
        font.features: { "tnum": 1 }
    }

    ShellText {
        id: _clock
        y: root.digitHeight - _clock.baselineOffset
        text: LockState.clockText
        color: Theme.text
        font.family: root.family
        font.weight: Font.ExtraLight
        font.pixelSize: root.clockSize
        font.letterSpacing: -0.04 * root.clockSize
        // proportional digits would shift the whole clock sideways every minute
        font.features: { "tnum": 1 }
    }

    ShellText {
        id: _date
        visible: root.showDate
        // the date's first letter starts where the clock's first digit does
        x: _clockLead.tightBoundingRect.x * root._clockK - _dateLead.tightBoundingRect.x * root._dateK
        y: root.digitHeight + root.dateGap - _date.baselineOffset
            - _dateCap.tightBoundingRect.y * root._dateK
        text: LockState.dateText
        color: Theme.subtext
        font.family: root.family
        font.pixelSize: root.dateSize
    }
}
