pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    property string armedLabel: "Confirm?"
    property int restWidth: 68
    property int armedWidth: 92
    property int designHeight: 30
    property bool busy: false
    property color tint: Theme.error

    readonly property bool _interactive: root.enabled && !root.busy
    readonly property bool armed: root._armed
    readonly property bool hovered: _hover.hovered

    signal confirmed()

    property bool _armed: false
    property real _armedAtMs: 0

    function request(): void {
        if (!root._interactive) return
        const now = Date.now()
        const age = now - root._armedAtMs
        // Input can reach a busy event loop before the expiry timer does.
        if (root._armed && (age < 0 || age >= _armTimer.interval)) root.disarm()
        if (root._armed) {
            // TapHandler fires once per tap, so a double-click would arm and confirm in one gesture
            if (age < Metrics.confirmGuardMs) return
            root.disarm()
            root.confirmed()
            return
        }
        root._armed = true
        root._armedAtMs = now
        _armTimer.restart()
    }

    function disarm(): void {
        root._armed = false
        _armTimer.stop()
    }

    Timer { id: _armTimer; interval: 3000; onTriggered: root._armed = false }

    // the pinned widths keep the menu's button steady; max() only ever grows it, so a
    // longer label cannot clip against them
    width:  visible ? Math.max(root._armed ? root.armedWidth : root.restWidth,
                               _row.implicitWidth + 20) : 0
    height: Metrics.rowHeightFor(root.designHeight)
    radius: Theme.radiusControl
    antialiasing: true
    onVisibleChanged: if (!visible) root.disarm()
    onEnabledChanged: if (!enabled) root.disarm()
    onBusyChanged: if (busy) root.disarm()

    // mix, not withAlpha: the notification popup window is transparent, so an alpha tint
    // would let the desktop through where the menu's opaque backdrop hides it. controlFill,
    // not a mix into menuControl: under glass that is a text-coloured wash, and mixing into
    // it drops the alpha that carried its darkness. Rest stays opaque too, or the
    // fade from a pale wash to a dark solid flashes bright between the endpoints
    color: root._armed
        ? Theme.controlFill(root.tint, _tap.pressed ? 0.28 : 0.16)
        : _tap.pressed ? Theme.controlFill(root.tint, 0.20)
        : _hover.hovered ? Theme.controlFill(Theme.subtext, 0.16) : Theme.controlFill(Theme.subtext, 0)

    opacity: root._interactive ? 1.0 : Theme.disabledOpacity

    OutlineBorder {
        radius: root.radius
        outlineWidth: root._armed ? 2 : 1
        outlineColor: root._armed
            ? Theme.withAlpha(root.tint, Theme.focusRingAlpha)
            : root.hovered ? Theme.menuControlLineHot : Theme.menuControlLine
        ColorFade on outlineColor {}
    }

    MotionBehavior on width {NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    ColorFade on color {}
    MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root._armed ? root.armedLabel : ""
    Accessible.focusable: root._interactive
    Accessible.onPressAction: root.request()

    HoverHandler {
        id: _hover
        enabled: root._interactive
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler { id: _tap; enabled: root._interactive; onTapped: root.request() }

    // the same ink-centering doctrine as Pill, but onto the label's capitals rather than the
    // box: the symbols fallback lends the glyph a taller line with a lower baseline, so
    // centering the two line boxes leaves the icon sitting under the word beside it.
    // The current glyph is its own reference: it is fixed per button and never trades
    // places with a sibling glyph, so there is no shared baseline to hold.
    // The ink is measured at 100px, as Settings measures the face: tightBoundingRect rounds
    // out to whole pixels, which at caption size is the size of the correction itself.
    // Unrounded, since QtRendering text has no pixel grid to land on. The glyph takes its y
    // from where the label actually sits rather than centering beside it: centering snaps
    // both to whole pixels, half a pixel apart whenever the row and a line differ in parity
    TextMetrics { id: _glyphInk; font.family: _glyphText.font.family; font.pixelSize: 100; text: root.glyph }
    TextMetrics {
        id: _capInk
        font.family: _labelText.font.family
        font.weight: _labelText.font.weight
        font.pixelSize: 100
        text: "H"
    }
    readonly property real _glyphInkY: root.glyph.length > 0
        ? _labelText.y + _labelText.baselineOffset
          + (_capInk.tightBoundingRect.y + _capInk.tightBoundingRect.height / 2) * _labelText.font.pixelSize / 100
          - _glyphText.baselineOffset
          - (_glyphInk.tightBoundingRect.y + _glyphInk.tightBoundingRect.height / 2) * _glyphText.font.pixelSize / 100
        : 0

    Row {
        id: _row
        anchors.centerIn: parent
        spacing: 6

        ShellText {
            id: _glyphText
            y: root._glyphInkY
            visible: root.glyph.length > 0
            text: root.glyph
            color: root._armed ? root.tint
                : _hover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.subtext, 0.72)
            font.pixelSize: Settings.fontSize
            ColorFade on color {}
        }

        ShellText {
            id: _labelText
            anchors.verticalCenter: parent.verticalCenter
            text: root._armed ? root.armedLabel : root.label
            color: root._armed ? root.tint
                : _hover.hovered ? Theme.withAlpha(Theme.text, 0.88) : Theme.withAlpha(Theme.text, 0.76)
            font.pixelSize: Settings.fontCaption
            font.weight: root._armed ? Font.DemiBold : Font.Normal
            ColorFade on color {}
        }
    }
}
