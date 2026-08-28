import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

// A single display-only condition chip in BatteryWidget's plain-Pill shape. This
// used to pair a REC chip with the mic one, but the recording indicator grew a
// timer and click-to-stop and moved to its own cluster (RecordingWidget); an open
// capture stream stays a passive privacy fact, so this chip stays passive too.
Pill {
    id: root

    readonly property bool _micInUse: Audio.micInUse

    readonly property bool show: _micInUse
    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001

    visible: layoutVisible
    opacity: _baseOpacity
    scale: show ? 1.0 : 0.7
    transformOrigin: Item.Center
    collapsed: !show
    interactive: false
    // Two states share this chip: an open capture stream, muted or not -- the open
    // stream is the privacy fact so the chip stays up either way, but the glyph
    // swaps to the slashed mic under mute (same re-enable BluetoothWidget does for
    // its own multi-state glyph) so the swap gets the stamp transition.
    animateGlyph: true
    shrinkDelay: 0

    MotionBehavior on _baseOpacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }
    MotionBehavior on scale        { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }

    // the pill's own text is empty until hover-expanded, which a screen reader never does
    accessibleName: Audio.sourceMuted ? "Microphone muted" : "Microphone in use"
    glyph: Audio.sourceMuted ? "󰍭" : "󰍬"
    // Fixed per the glyphAlignReference doctrine: the reference is a stamp anchor,
    // not a mirror of current state, so it stays on the unmuted glyph the two share.
    glyphAlignReference: "󰍬"
    glyphPixelSize: Settings.iconSize + 1
    glyphColor: Theme.warning
    textColor: Theme.warning
    text: expanded ? (Audio.sourceMuted ? "Mic muted" : "Mic in use") : ""
}
