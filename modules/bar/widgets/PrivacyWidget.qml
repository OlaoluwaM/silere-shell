import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

// Two independent condition chips, not a StatusActionPill: recording and mic-in-use
// are unrelated signals with their own glyphs, so each needs to appear/disappear on
// its own the way VitalsWidget's CPU/MEM/TEMP chips do rather than sharing one slot.
// Recording rides Theme.error -- the strongest signal in the design language, same
// tier Battery.critical claims -- since a live screen recording is the one state here
// that can leak more than the person watching the bar expects.
Item {
    id: root

    property bool compact: ShellSettings.barCompact

    readonly property bool _recording: Recording.recording
    readonly property bool _micInUse: Audio.micInUse

    readonly property bool show: root._recording || root._micInUse
    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001

    visible: layoutVisible
    opacity: _baseOpacity
    implicitWidth: _row.implicitWidth
    implicitHeight: Metrics.barRowHeight

    MotionBehavior on _baseOpacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    Row {
        id: _row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.pillGapFor(root.compact)

        Pill {
            id: _recChip
            anchors.verticalCenter: parent.verticalCenter
            height: root.height
            compact: root.compact
            interactive: false
            animateGlyph: false
            shrinkDelay: 0
            collapsed: !root._recording
            visible: root._recording || opacity > 0.001
            opacity: root._recording ? 1.0 : 0.0
            scale: root._recording ? 1.0 : 0.7
            transformOrigin: Item.Center
            MotionBehavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            MotionBehavior on scale   { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }
            glyph: "󰑊"
            glyphAlignReference: "󰑊"
            glyphPixelSize: Settings.iconSize + 1
            glyphColor: Theme.error
            textColor: Theme.error
            text: expanded ? "REC" : ""
        }

        Pill {
            id: _micChip
            anchors.verticalCenter: parent.verticalCenter
            height: root.height
            compact: root.compact
            interactive: false
            // Two states share this chip now: an open capture stream, muted or not --
            // the open stream is the privacy fact so the chip stays up either way, but
            // the glyph swaps to the slashed mic under mute (same re-enable BluetoothWidget
            // does for its own multi-state glyph) so the swap gets the stamp transition.
            animateGlyph: true
            shrinkDelay: 0
            collapsed: !root._micInUse
            visible: root._micInUse || opacity > 0.001
            opacity: root._micInUse ? 1.0 : 0.0
            scale: root._micInUse ? 1.0 : 0.7
            transformOrigin: Item.Center
            MotionBehavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            MotionBehavior on scale   { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }
            glyph: Audio.sourceMuted ? "󰍭" : "󰍬"
            // Fixed per the glyphAlignReference doctrine: the reference is a stamp anchor,
            // not a mirror of current state, so it stays on the unmuted glyph the two share.
            glyphAlignReference: "󰍬"
            glyphPixelSize: Settings.iconSize + 1
            glyphColor: Theme.warning
            textColor: Theme.warning
            text: expanded ? (Audio.sourceMuted ? "Mic muted" : "Mic in use") : ""
        }
    }
}
