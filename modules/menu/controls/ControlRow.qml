import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

MenuRow {
    id: root

    property string label:       ""
    property string status:      ""
    property string valueText:   ""
    property color  accentColor: Theme.accent
    // transparent follows the normal active/inactive hierarchy. A semantic colour lets a failure remain recognisable even when the control is off
    property color  statusColor: "transparent"
    property bool   active:       false
    property bool   available:    true
    property bool   showSwitch:   false
    property bool   expandable:   false
    property bool   expanded:     false
    // trailing button that opens a surface of its own instead of unfolding in place: it takes the chevron's slot and hit area, shows the onward chevron the settings rows use, which never turns, and announces itself through opened()
    property bool   opensCard:    false
    property bool   passive:      false
    // a value that is a call to action, not a datum: it reads as accent like an armed row does
    property bool   valueIsAction: false

    rowHovered:     _hover.hovered
    rowPressed:     _tap.pressed
    rowInteractive: root._canTap

    signal activated()
    signal expandToggled()
    signal opened()

    readonly property bool _canTap: !root.passive && root.enabled && root.visible && root.available
    function _activate(): void {
        if (!_canTap) return
        // animate the knob only on a real user flip, not section-driven re-checks
        if (showSwitch) _switch.armFlipAnimation()
        root.activated()
    }

    readonly property bool _hasSlot: root.expandable || root.opensCard

    function _pressSlot(): void {
        if (!root._canTap) return
        if (root.opensCard) root.opened()
        else if (root.expandable) root.expandToggled()
    }

    function _insideChevron(pos): bool {
        if (!root._hasSlot || !_chevron.visible) return false
        const x0 = _rightSlot.x + _chevron.x - 4
        const x1 = _rightSlot.x + _chevron.x + _chevron.width + 4
        return pos.x >= x0 && pos.x <= x1
    }

    height:         Metrics.rowHeightFor(48)

    // Visibility gates input, but should not change the resting appearance.
    opacity: root.passive || (root.enabled && root.available) ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity {NumberAnimation { duration: Motion.medium } }

    Accessible.role: root.showSwitch ? Accessible.CheckBox
        : root._canTap ? Accessible.Button : Accessible.StaticText
    Accessible.name: root.label
    Accessible.description: root.status.length > 0 && root.valueText.length > 0
        ? root.status + " · " + root.valueText
        : root.status.length > 0 ? root.status : root.valueText
    Accessible.focusable: root._canTap
    Accessible.checkable: root.showSwitch
    Accessible.checked: root.showSwitch && root.active
    Accessible.onPressAction: root._activate()

    HoverHandler { id: _hover; cursorShape: root._canTap ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        id: _tap
        enabled: root._canTap
        onTapped: (eventPoint) => {
            if (!root._insideChevron(eventPoint.position)) {
                root._activate()
            }
        }
    }

    Item {
        id: _iconSlot
        anchors.left:           parent.left
        anchors.leftMargin:     14
        anchors.verticalCenter: parent.verticalCenter
        width: 18; height: 18

        ShellText {
            id: _glyph
            anchors.centerIn: parent
            text:           root.glyph
            color:          root.active ? Theme.withAlpha(root.accentColor, 0.95)
                                        : Theme.withAlpha(Theme.subtext, 0.85)
            font.pixelSize: Settings.iconSize + 2
            ColorFade on color {}
        }
    }

    Column {
        id: _textCol
        anchors.left:           _iconSlot.right
        anchors.leftMargin:     10
        anchors.right:          _rightSlot.left
        anchors.rightMargin:    10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        ShellText {
            width:          parent.width
            text:           root.label
            color:          root.active ? Theme.text : Theme.withAlpha(Theme.text, 0.85)
            font.pixelSize: Settings.fontSize
            font.weight:    Font.DemiBold
            elide:          Text.ElideRight
            ColorFade on color {}
        }

        ShellText {
            visible:        root.status.length > 0
            width:          parent.width
            text:           root.status
            color:          root.statusColor.a > 0
                ? Theme.withAlpha(Theme.mix(root.statusColor, Theme.text,
                    ShellSettings.highContrast ? 0.22 : 0.10), 0.94)
                : root.active ? Theme.mix(root.accentColor, Theme.text, 0.12)
                              : Theme.withAlpha(Theme.subtext, 0.62)
            font.pixelSize: Settings.fontCaption
            font.weight:    Font.Medium
            elide:          Text.ElideRight
            ColorFade on color {}
        }
    }

    Item {
        id: _rightSlot
        anchors.right:          parent.right
        anchors.rightMargin:    12
        anchors.verticalCenter: parent.verticalCenter
        height: root.height
        readonly property real _chevronW: _chevron.visible ? _chevron.width + 8 : 0
        readonly property real _valNatural: Math.ceil(_valMetrics.advanceWidth)
        // the label names the setting and the value only qualifies it, so a long value
        // gives way first: 42 of label inset + 22 of margins + the same 96 label floor
        // SelectRow reserves. Uncapped, the value took its full width and elided the label.
        readonly property real _valMax: Math.max(0, root.width - 160 - _chevronW)
        readonly property real _ctrlW: root.showSwitch ? 36
            : root.valueText.length === 0 ? 0
            : root.width <= 0 ? _valNatural
            : Math.min(_valNatural, _valMax)
        width: _chevronW + _ctrlW

        TextMetrics { id: _valMetrics; font.family: Settings.font; font.pixelSize: Settings.fontLabel; text: root.valueText }

        ToggleSwitch {
            id: _switch
            visible: root.showSwitch
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked:     root.active
            highlighted: _hover.hovered && root._canTap
            pressed: _tap.pressed
            accentColor: root.accentColor
        }

        ShellText {
            visible: !root.showSwitch && root.valueText.length > 0
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            width:          _rightSlot._ctrlW
            horizontalAlignment: Text.AlignRight
            elide:          Text.ElideRight
            text:           root.valueText
            color:          (root.active || (root.valueIsAction && root._canTap))
                                ? Theme.mix(root.accentColor, Theme.text, 0.18)
                                : Theme.withAlpha(Theme.text, 0.60)
            font.pixelSize: Settings.fontLabel
            font.weight:    Font.Medium
            ColorFade on color {}
        }

        // MouseArea (not TapHandler) so it doesn't fire the row body tap too
        Item {
            id: _chevron
            visible: root._hasSlot
            width:  visible ? 24 : 0
            height: parent.height
            anchors.right: (root.showSwitch || root.valueText.length > 0) ? undefined : parent.right
            x: (root.showSwitch || root.valueText.length > 0)
                ? parent.width - _rightSlot._ctrlW - 8 - width
                : 0

            // not announced for an expandable row: its row already carries the state, and a bare chevron says nothing
            Accessible.ignored: !root.opensCard
            Accessible.role: Accessible.Button
            Accessible.name: "Open " + root.label
            Accessible.focusable: root.opensCard && root._canTap
            Accessible.onPressAction: root._pressSlot()

            ShellText {
                anchors.centerIn: parent
                text: root.opensCard ? "󰅂" : "󰅀"
                color: (_chevHover.hovered) ? Theme.text
                     : Theme.withAlpha(Theme.subtext, root.expanded ? 0.85 : 0.55)
                font.pixelSize: Settings.fontSize
                rotation: root.expanded && !root.opensCard ? 180 : 0
                transformOrigin: Item.Center
                Disclosure on rotation { list: true }
                ColorFade on color {}
            }

            HoverHandler { id: _chevHover; enabled: root._hasSlot; cursorShape: Qt.PointingHandCursor }
            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: -4
                anchors.rightMargin: -4
                enabled: root._hasSlot
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root._pressSlot()
                }
            }
        }
    }
}
