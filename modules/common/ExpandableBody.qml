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
    readonly property bool truncated: bodyLabel.truncated

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
        visible: root.expanded || bodyLabel.truncated
        width: root.width
        height: visible ? Math.max(16, disclosureLabel.implicitHeight) : 0

        Item {
            width: disclosureLabel.implicitWidth + 2 + disclosureChevron.width
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

            Item {
                id: disclosureChevron
                width: 16
                height: 16
                anchors {
                    left: disclosureLabel.right
                    leftMargin: 2
                    verticalCenter: parent.verticalCenter
                }

                ShellText {
                    anchors.centerIn: parent
                    text: "󰅀"
                    color: disclosureHover.hovered
                        ? Theme.accent : Theme.withAlpha(Theme.accent, 0.78)
                    font.pixelSize: Settings.fontCaption
                    rotation: root.expanded ? 180 : 0
                    transformOrigin: Item.Center
                    MotionBehavior on rotation {
                        NumberAnimation {
                            duration: Motion.fast
                            easing.type: Easing.OutCubic
                        }
                    }
                    ColorFade on color {}
                }
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
