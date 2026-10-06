pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

Column {
    id: root

    property string bodyText: ""
    property color bodyColor: Theme.menuTextMuted
    property int fontPixelSize: Settings.fontLabel
    property int collapsedLineCount: 2
    property int expandedLineCount: 12
    property bool expanded: false
    // a host that owns the tap (a folded stack) hides the pill so one tap means one thing
    property bool showDisclosure: true
    readonly property bool truncated: bodyLabel.truncated
    readonly property bool _disclosed: root.showDisclosure && (root.expanded || bodyLabel.truncated)
    readonly property real _pillHeight: Math.max(16, disclosureLabel.implicitHeight)
    // a Column reports implicitHeight on its next polish, a frame after the text re-wraps,
    // so a host that lays out from the body's height (a list row) reads this instead. It
    // follows the pill's condition rather than its visibility, which a hidden page clears
    readonly property real contentHeight: bodyLabel.implicitHeight
        + (root._disclosed ? root.spacing + root._pillHeight : 0)

    visible: bodyText.length > 0
    spacing: 5

    function toggle(): void {
        if (root.expanded || bodyLabel.truncated)
            root.expanded = !root.expanded
    }

    ShellText {
        id: bodyLabel
        width: root.width
        text: root.bodyText
        color: root.bodyColor
        font.pixelSize: root.fontPixelSize
        wrapMode: Text.Wrap
        maximumLineCount: root.expanded
            ? root.expandedLineCount : root.collapsedLineCount
        elide: Text.ElideRight
    }

    Item {
        id: disclosure
        visible: root._disclosed
        width: root.width
        height: root._disclosed ? root._pillHeight : 0

        Item {
            width: disclosureLabel.implicitWidth
            height: parent.height

            Accessible.role: Accessible.Button
            Accessible.name: root.expanded ? qsTr("Show less") : qsTr("Show more")
            Accessible.focusable: true
            Accessible.onPressAction: root.toggle()

            ShellText {
                id: disclosureLabel
                anchors.verticalCenter: parent.verticalCenter
                text: root.expanded ? qsTr("Less") : qsTr("More")
                color: disclosureHover.hovered
                    ? Theme.accent : Theme.withAlpha(Theme.accent, 0.78)
                font.pixelSize: Settings.fontLabel
                font.weight: Font.Medium
                ColorFade on color {}
            }

            HoverHandler {
                id: disclosureHover
                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: root.toggle()
            }
        }
    }
}
