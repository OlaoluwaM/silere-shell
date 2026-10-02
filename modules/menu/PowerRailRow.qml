pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "controls"

Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    property string value: ""
    property bool interactive: true
    property bool dangerous: false
    property bool confirm: false
    readonly property bool armed: _confirm.armed
    property bool tintedGlyph: false
    property string confirmLabel: "Press again"
    property int confirmTimeout: 3000
    property color accentColor: Theme.accent

    signal triggered()

    // single-target row -- any non-empty key means "this row is armed", so the
    // key itself carries no meaning beyond that
    ArmConfirm { id: _confirm; interval: root.confirmTimeout }

    readonly property bool _hot: root.enabled && root.interactive && (_hover.hovered)
    readonly property bool _showValue: root.value.length > 0 && !root.armed
    // the rail's width is fixed while its text grows, so at raised uiScale the value crowded
    // the label out; a clipped "Mod…" loses the row's identity where a clipped value still
    // reads, so the value yields first. 62 = the label's left offset plus the gap before it
    TextMetrics {
        id: _labelInk
        text: root.armed ? root.confirmLabel : root.label
        font {
            family:    Settings.font
            pixelSize: Settings.fontLabel
            weight:    root.armed ? Font.DemiBold : Font.Normal
        }
    }
    readonly property int _valueMaxW: Math.max(42, Math.min(86,
        Math.round(root.width * 0.52),
        root.width - 62 - Math.ceil(_labelInk.advanceWidth) - 1))
    // the yielded value still has to be readable somewhere; the rail clips anything outside it,
    // so the hint reveals the full value in place over the row rather than floating beside it
    readonly property bool _hintWanted: root._hot && root._showValue && _value.truncated
    property bool _hintReady: false
    on_HintWantedChanged: {
        if (root._hintWanted) {
            _hintDelay.restart()
        } else {
            _hintDelay.stop()
            root._hintReady = false
        }
    }
    // the bar's dwell, so a sweep down the rail toward Lock passes this row without a flash
    Timer {
        id: _hintDelay
        interval: BarHintState.showDelay
        onTriggered: root._hintReady = root._hintWanted
    }
    property real _shift: root._hot || root.armed ? 0.5 : 0.0
    readonly property color _fg: root.armed
        ? Theme.text
        : root.dangerous
            ? Theme.mix(Theme.text, Theme.error, root._hot ? 0.18 : 0.08)
            : Theme.withAlpha(Theme.mix(Theme.subtext, Theme.text, 0.18), root._hot ? 0.94 : 0.78)
    readonly property color _glyphFg: root.armed
        ? Theme.error
        : root.tintedGlyph
            ? Theme.withAlpha(root.accentColor, root.interactive ? (root._hot ? 0.90 : 0.72) : 0.86)
            : root.dangerous
                ? Theme.withAlpha(Theme.error, root._hot ? 0.86 : 0.60)
                : Theme.withAlpha(Theme.subtext, root._hot ? 0.78 : 0.56)

    width: parent ? parent.width : implicitWidth
    height: Metrics.rowHeightFor(30)
    radius: Theme.radiusInline
    antialiasing: true
    opacity: root.enabled ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }
    color: root.armed
        ? Theme.withAlpha(Theme.error, 0.105)
        : _tap.pressed
            ? Theme.withAlpha(root.dangerous ? Theme.error : root.accentColor, 0.13)
        : root._hot ? Theme.withAlpha(Theme.text, 0.045) : "transparent"

    Accessible.role: root.interactive ? Accessible.Button : Accessible.StaticText
    Accessible.name: root.armed ? root.confirmLabel : root.label
    Accessible.description: root.value
    Accessible.focusable: root.enabled && root.interactive
    Accessible.onPressAction: root.activate()

    OutlineBorder {
        radius: root.radius
        outlineWidth: 2
        outlineColor: "transparent"
        ColorFade on outlineColor {}
    }

    function disarm(): void {
        _confirm.disarm()
    }

    function activate(): void {
        if (!root.enabled || !root.interactive) return
        if (!root.confirm) { root.triggered(); return }
        if (_confirm.tryConfirm("armed")) root.triggered()
    }

    onEnabledChanged: if (!root.enabled) root.disarm()
    onInteractiveChanged: if (!root.interactive) root.disarm()
    onConfirmChanged: if (!root.confirm) root.disarm()

    onArmedChanged: {
        _confirmDrain.stop()
        if (!root.armed) {
            root._confirmProgress = 0.0
            return
        }
        root._confirmProgress = 1.0
        if (!ShellSettings.reduceMotion) _confirmDrain.start()
    }

    property real _confirmProgress: 0.0

    // one run-to-completion animation: it is clock-driven so a delayed frame never extends
    // the window, and it costs no per-tick script. The duration is the disarm timeout
    // itself, which Motion must not scale or the ring would lie
    NumberAnimation {
        id: _confirmDrain
        target: root
        property: "_confirmProgress"
        from: 1.0
        to: 0.0
        duration: Math.max(1, root.confirmTimeout)
        easing.type: Easing.Linear
    }

    PerimeterProgress {
        anchors.fill: parent
        // the animation that drains this is a motion gate, so under reduce motion the ring
        // would sit full for the whole window and read as "nothing is expiring"
        visible: root.armed && !ShellSettings.reduceMotion
        inset:        1.0
        cornerRadius: root.radius
        progress:     root._confirmProgress
        trackColor:   Theme.menuControlLine
        arcColor:     Theme.withAlpha(Theme.error, 0.72)
    }

    HoverHandler {
        id: _hover
        enabled: root.enabled && root.interactive
        cursorShape: root.enabled && root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        id: _tap
        enabled: root.enabled && root.interactive
        onTapped: root.activate()
    }

    ColorFade on color {}
    MotionBehavior on _shift {
        NumberAnimation { duration: Motion.ms(105); easing.type: Easing.OutCubic }
    }

    ShellText {
        id: _glyph
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        horizontalAlignment: Text.AlignHCenter
        text: root.glyph
        color: root._glyphFg
        font.pixelSize: Settings.fontSize
        transform: Translate { x: root._shift }
        ColorFade on color {}
    }

    ShellText {
        id: _value
        visible: root._showValue
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root._valueMaxW)
        text: root.value
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        color: Theme.withAlpha(Theme.menuTextMuted, root._hot ? 0.84 : 0.66)
        font.pixelSize: Settings.fontCaption
        font.weight: Font.Medium
        ColorFade on color {}
    }

    ShellText {
        anchors.left: _glyph.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: root._showValue ? Math.round(_value.width + 20) : 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.armed ? root.confirmLabel : root.label
        elide: Text.ElideRight
        color: root._fg
        font.pixelSize: Settings.fontLabel
        font.weight: root.armed ? Font.DemiBold : Font.Normal
        transform: Translate { x: root._shift }
        ColorFade on color {}
    }

    Rectangle {
        id: _hint
        readonly property bool _show: root._hintWanted && root._hintReady

        // 9px padding puts the hint's text exactly where the elided value's sits
        anchors.right: parent.right
        anchors.rightMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(_hintLabel.implicitWidth + 18, root.width - 6)
        height: 22; radius: Theme.radiusInline
        // menuHint, not menuCard: this paints over the row's own label, so under glass it must be opaque
        color: Theme.menuHint
        antialiasing: true
        opacity: _show ? 1.0 : 0.0
        scale:   _show ? 1.0 : 0.96
        transformOrigin: Item.Right
        visible: opacity > 0.01

        OutlineBorder {
            radius: _hint.radius
            outlineColor: Theme.menuCardBorder
        }
        MotionBehavior on opacity {
            id: _hintFade
            NumberAnimation { duration: _hintFade.targetValue > 0.5 ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
        }
        MotionBehavior on scale {
            id: _hintScale
            NumberAnimation { duration: _hintScale.targetValue >= 1 ? Motion.fast : Motion.instant; easing.type: Easing.OutCubic }
        }
        ShellText {
            id: _hintLabel
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - 18)
            text: root.value
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.text, 0.78)
            font.pixelSize: Settings.fontCaption
            font.weight: Font.Medium
        }
    }
}
