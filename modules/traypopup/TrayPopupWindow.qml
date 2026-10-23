pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../../config"
import "../../services"
import "../common"

OverlayPopupWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property int rowWidth: 260
    readonly property int iconSize: Settings.iconSize + 2

    screen: targetScreen
    popupState: TrayPopupState
    layerNamespace: "silere-traypopup"
    popupCard: card

    // right-click (or the item's own onlyMenu fallback) hands the item's menu to
    // the same TrayMenuState/TrayMenuPopup plumbing TrayWidget's bar row uses --
    // anchored to this row instead of a bar tile
    function _openItemMenu(item, row): void {
        if (!item.hasMenu) return
        row.syncMenuAnchor()
        TrayMenuState.toggleAt(
            row.menuAnchorX,
            win.targetScreen,
            item.menu,
            Metrics.barAtBottom,
            row,
            item,
            true
        )
    }

    function _activateItem(item, row): void {
        if (!WindowActions.focusTrayItem(item.id, item.title, item.tooltipTitle)) {
            if (item.onlyMenu) win._openItemMenu(item, row)
            else item.activate()
        }
    }

    // rows don't move on their own once laid out (scrolling only shifts the
    // Flickable's contentItem, not each row's x), so a menu anchor only goes
    // stale when the card itself slides during placement
    function _syncRowAnchors(): void {
        for (let i = 0; i < _rows.count; i++) {
            const row = _rows.itemAt(i)
            if (row) row.syncMenuAnchor()
        }
    }

    FloatingPopupCard {
        id: card
        win: win
        open: TrayPopupState.open
        anchorX: TrayPopupState.effectiveAnchorX
        barBottom: Metrics.barAtBottom

        readonly property int pad: 6
        readonly property real _maxContentH: Math.max(48, win.height - _edgeY - pad * 2 - 8)

        width:  win.rowWidth + pad * 2
        height: Math.min(_col.implicitHeight, _maxContentH) + pad * 2

        onXChanged: win._syncRowAnchors()

        Binding {
            target: TrayPopupState
            property: "cardRect"
            value: Qt.rect(card.x, card.y, card.width, card.height)
        }

        Connections {
            target: TrayPopupState
            function onOpenChanged() { if (TrayPopupState.open) card.forceActiveFocus() }
        }
        Component.onCompleted: if (TrayPopupState.open) card.forceActiveFocus()

        ShellFlickable {
            id: _scroll
            x: card.pad; y: card.pad
            width: win.rowWidth
            height: Math.max(0, card.height - card.pad * 2)
            contentWidth: width
            contentHeight: _col.implicitHeight
            interactive: contentHeight > height

            Column {
                id: _col
                width: win.rowWidth
                spacing: 1

                Repeater {
                    id: _rows
                    model: SystemTray.items

                    delegate: Item {
                        id: _row
                        required property var modelData

                        readonly property string label: SafeText.singleLineText(
                            String(modelData.tooltipTitle || "").length > 0 ? modelData.tooltipTitle
                            : String(modelData.title || "").length > 0 ? modelData.title
                            : modelData.id, 128)
                        readonly property string iconSource: IconResolver.trayIconSource(modelData.icon)
                        readonly property bool passive: modelData.status === Status.Passive
                        property real menuAnchorX: 0
                        property bool _fallbackDue: false

                        function syncMenuAnchor(): void {
                            const pt = _row.mapToItem(null, win.iconSize / 2 + 12, 0)
                            if (isFinite(pt.x)) _row.menuAnchorX = pt.x
                        }
                        Component.onCompleted: _row.syncMenuAnchor()
                        onXChanged: _row.syncMenuAnchor()

                        width: parent ? parent.width : 0
                        height: Metrics.rowHeightFor(32)
                        opacity: passive ? 0.78 : 1.0
                        MotionBehavior on opacity { NumberAnimation { duration: Motion.color } }

                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusControl
                            antialiasing: true
                            color: (_rowHover.hovered || _tap.pressed)
                                ? Theme.withAlpha(Theme.menuHover, 0.08) : "transparent"
                            ColorFade on color {}
                        }

                        HoverHandler { id: _rowHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            id: _tap
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onTapped: (eventPoint, button) => {
                                if (button === Qt.RightButton) win._openItemMenu(_row.modelData, _row)
                                else win._activateItem(_row.modelData, _row)
                            }
                        }

                        Timer {
                            interval: 300
                            running: !_icon.ready
                            onTriggered: _row._fallbackDue = true
                        }

                        Rectangle {
                            width: win.iconSize
                            height: win.iconSize
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            radius: width / 2
                            color: Theme.withAlpha(Theme.subtext, 0.12)
                            visible: !_icon.ready && _row._fallbackDue

                            ShellText {
                                anchors.centerIn: parent
                                text: SafeText.initial(_row.label, "?")
                                color: Theme.subtext
                                font.pixelSize: Math.max(9, Math.round(win.iconSize * 0.68))
                            }
                        }

                        IconImage {
                            id: _icon
                            readonly property bool ready: status === Image.Ready
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: win.iconSize
                            height: win.iconSize
                            implicitSize: win.iconSize
                            source: _row.iconSource
                            backer.sourceSize.width: 64
                            backer.sourceSize.height: 64
                            mipmap: true
                            asynchronous: true
                            visible: opacity > 0.01
                            opacity: ready ? 1.0 : 0.0
                            MotionBehavior on opacity { NumberAnimation { duration: Motion.fast } }
                        }

                        ShellText {
                            anchors.left: _icon.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: _row.label
                            elide: Text.ElideRight
                            color: Theme.text
                            font.pixelSize: Settings.fontSize
                        }
                    }
                }
            }
        }

        ListEdgeLines {
            anchors.fill: _scroll
            visible: _scroll.interactive
            list: _scroll
        }
    }
}
