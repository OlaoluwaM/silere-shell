import QtQuick
import "../../../config"
import "../../common"

// one option of a pick-one list that spells out what each choice does; sibling to
// ChoiceChipRow for the choices that need a sentence rather than a chip
MenuRow {
    id: root

    property var    value
    property string label:       ""
    property string description: ""
    // names the list the option belongs to, which a lone radio button would not announce
    property string groupName:   ""
    property bool   active:      false
    property color  accentColor: Theme.accent

    rowHovered:     _hover.hovered
    rowPressed:     _tap.pressed
    rowInteractive: root.enabled

    signal chosen(var value)

    readonly property bool _hasDetail: root.description.length > 0
    readonly property int _descPadV: 11
    // same grid as ToggleRow: a described row grows to its text, a bare one is a
    // single-line settings row
    height: _hasDetail ? 4 * Math.ceil((_descPadV * 2 + _textCol.implicitHeight) / 4)
                       : Metrics.rowHeightFor(44)

    opacity: root.enabled ? 1.0 : Theme.disabledOpacity
    MotionBehavior on opacity { NumberAnimation { duration: Motion.medium } }

    Accessible.role: Accessible.RadioButton
    Accessible.name: root.groupName.length > 0 ? root.groupName + ": " + root.label : root.label
    Accessible.description: root.description
    Accessible.focusable: root.enabled
    Accessible.checkable: true
    Accessible.checked: root.active
    Accessible.onPressAction: if (root.enabled) root.chosen(root.value)

    HoverHandler {
        id: _hover
        enabled: root.enabled
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }
    TapHandler {
        id: _tap
        enabled: root.enabled
        onTapped: root.chosen(root.value)
    }

    Column {
        id: _textCol
        anchors.left:           parent.left
        anchors.leftMargin:     14
        anchors.right:          _mark.left
        anchors.rightMargin:    10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        ShellText {
            width: parent.width
            text:  root.label
            elide: Text.ElideRight
            color: root.active ? Theme.text : Theme.subtext
            font.pixelSize: Settings.fontSize
            ColorFade on color {}
        }

        ShellText {
            visible: root._hasDetail
            width:   parent.width
            text:    root.description
            elide:   Text.ElideRight
            color:   Theme.menuTextDetail
            font.pixelSize: Settings.fontCaption
        }
    }

    Rectangle {
        id: _mark
        anchors.right:          parent.right
        anchors.rightMargin:    14
        anchors.verticalCenter: parent.verticalCenter
        width:  14
        height: 14
        // a rounded square, not a dot: the shell's controls are rounded rectangles
        radius: 4
        antialiasing: true
        color: root.active ? root.accentColor : "transparent"
        ColorFade on color {}

        OutlineBorder {
            radius: _mark.radius
            outlineColor: root.active ? "transparent"
                : _hover.hovered ? Theme.menuControlLineHot : Theme.menuControlLine
            ColorFade on outlineColor {}
        }
    }
}
