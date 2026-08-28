pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property string _output: Compositor.monitorName(win.screen)
    readonly property int menuWidth: 220
    readonly property int menuRowHeight: Metrics.rowHeightFor(32)

    property var _activeMenu: null
    property bool _rootOpenedSent: false

    function _menuRoot(): var {
        return win._activeMenu?.menu ?? win._activeMenu
    }
    function _emitMenuSignal(entry, signalName: string, fallbackName: string): bool {
        if (entry === null || entry === undefined) return false
        try {
            const fn = entry[signalName]
            if (typeof fn === "function") {
                fn()
                return true
            }

            const fallback = entry[fallbackName]
            if (typeof fallback === "function") {
                fallback()
                return true
            }
        } catch (error) {
            console.warn("silere-shell: tray menu signal failed:", String(error))
            return false
        }

        console.warn("silere-shell: tray menu entry has no", signalName, "signal")
        return false
    }
    function _sendRootOpened(): void {
        if (_rootOpenedSent || !TrayMenuState.open) return
        if (_emitMenuSignal(_menuRoot(), "opened", "sendOpened"))
            _rootOpenedSent = true
    }
    function _sendRootClosed(): void {
        if (!_rootOpenedSent) return
        _emitMenuSignal(_menuRoot(), "closed", "sendClosed")
        _rootOpenedSent = false
    }
    function _setActiveMenu(handle): void {
        if (win._activeMenu === handle) {
            // a quick close/reopen reuses the handle: same object identity, but the previous close already cleared the sent flag
            if (handle !== null) win._sendRootOpened()
            return
        }
        win._sendRootClosed()
        win._activeMenu = handle
        win._sendRootOpened()
    }
    function _closeFlyouts(): void {
        const kids = win.contentItem.children
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (k && k.opened === true) k.opened = false
        }
    }
    function _drillIntoFlyout(flyout, menu): void {
        flyout["_drillInto"](menu)
    }
    function _flyoutLaneFits(flyout, laneX: real): bool {
        if (laneX < 0 || laneX + flyout._w > win.width) return false

        // A cascade may share vertical space, but never the horizontal lane of an ancestor.
        if (laneX < card.x + card.width && laneX + flyout._w > card.x) return false

        let ancestor = flyout._parentFlyout
        while (ancestor !== null) {
            if (ancestor.opened
                && laneX < ancestor.x + ancestor.width
                && laneX + flyout._w > ancestor.x)
                return false
            ancestor = ancestor._parentFlyout
        }
        return true
    }

    onVisibleChanged: if (!visible) win._setActiveMenu(null)
    // the handle is set before this popup exists, so seed from the current state on creation
    Component.onCompleted: if (TrayMenuState.menuHandle !== null) win._setActiveMenu(TrayMenuState.menuHandle)
    Connections {
        target: TrayMenuState
        function onMenuHandleChanged() {
            if (TrayMenuState.menuHandle !== null) win._setActiveMenu(TrayMenuState.menuHandle)
        }
    }

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && TrayMenuState.open) TrayMenuState.close()
        }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-traymenu"
    WlrLayershell.keyboardFocus: TrayMenuState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: TrayMenuState.open || card.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut { sequence: "Escape"; context: Qt.ApplicationShortcut; enabled: TrayMenuState.open; onActivated: TrayMenuState.close() }

    OutsideTapGuard {
        id: _tapGuard
        open: TrayMenuState.open
    }

    Connections {
        target: TrayMenuState
        function onOpenChanged() {
            if (!TrayMenuState.open) {
                win._closeFlyouts()
                win._sendRootClosed()
            } else {
                win._sendRootOpened()
            }
        }
    }

    QsMenuOpener {
        id: _opener
        menu: win._menuRoot()
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: TrayMenuState.open ? _fillArea : null }

    // submenu flyouts sit outside the card, as siblings of it under contentItem
    function _overFlyout(p: point): bool {
        const kids = win.contentItem.children
        for (let i = 0; i < kids.length; i++) {
            const k = kids[i]
            if (!k || k.opened !== true || !k.visible) continue
            if (p.x >= k.x && p.x <= k.x + k.width &&
                p.y >= k.y && p.y <= k.y + k.height) return true
        }
        return false
    }

    TapHandler {
        id: _dismiss
        enabled: TrayMenuState.open && card.scaleAmt > 0.95
        // a TapHandler keeps a passive grab, so this fires for taps on rows too
        onTapped: {
            if (_tapGuard.ignoring) return
            const p = _dismiss.point.position
            if (win._overFlyout(p)) return
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                TrayMenuState.close()
        }
    }

    Component {
        id: _rowDelegate

        Item {
            id: _entry
            required property var modelData
            // submenu rows only: lets Left-arrow close the right flyout, reparented to the window root and no longer bubbling keys up
            property Item ownerFlyout: null
            property Flickable ownerScroll: null
            property int menuDepth: 0

            readonly property bool sep:       modelData?.isSeparator ?? false
            readonly property bool on:        (modelData?.enabled ?? true) && !sep
            readonly property bool sub:       (modelData?.hasChildren ?? false)
                && menuDepth < 8
            readonly property int  btnType:   modelData?.buttonType ?? 0
            readonly property bool checkable: btnType !== 0
            readonly property bool checked:   (modelData?.checkState ?? Qt.Unchecked) === Qt.Checked
            readonly property string label: SafeText.singleLineText(modelData?.text, 256)
            readonly property string iconSrc: IconResolver.iconSource(modelData?.icon)

            width: win.menuWidth
            height: sep ? 11 : win.menuRowHeight

            function closeFlyout(): void {
                if (_flyout.opened) _flyout.opened = false
            }
            function _openFlyout(allowAdaptiveExpansion: bool): void {
                if (!_entry.sub || _flyout.opened) return
                _flyout._syncOrigin()
                if (_flyout._adaptiveExpansion && !allowAdaptiveExpansion) return

                // one visible child branch per menu branch; closing the siblings releases their nested models
                const sibs = _entry.parent ? _entry.parent.children : []
                for (let k = 0; k < sibs.length; k++) {
                    const c = sibs[k]
                    if (c !== _entry && c && typeof c.closeFlyout === "function")
                        c.closeFlyout()
                }
                if (_flyout._needsDrillIn) {
                    win._drillIntoFlyout(_entry.ownerFlyout, _entry.modelData)
                    return
                }
                _flyout._prepareToOpen()
                _flyout.opened = true
            }
            function _toggleFlyout(): void {
                if (_flyout.opened) _entry.closeFlyout()
                else _entry._openFlyout(true)
            }
            Hairline {
                visible: _entry.sep
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.menuDivider
            }

            Rectangle {
                visible: !_entry.sep
                anchors.fill: parent
                radius: Theme.radiusControl
                antialiasing: true
                color: (_entry.on && (_rowHover.hovered || _flyout.opened))
                    ? Theme.withAlpha(Theme.menuHover, 0.08) : "transparent"
                ColorFade on color {}
            }

            HoverHandler {
                id: _rowHover
                enabled: _entry.on
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: if (hovered && _entry.sub) _entry._openFlyout(false)
            }
            TapHandler {
                enabled: _entry.on && !_entry.sub
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                    win._emitMenuSignal(_entry.modelData, "triggered", "sendTriggered")
                    TrayMenuState.close()
                }
            }
            TapHandler {
                enabled: _entry.on && _entry.sub
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: _entry._toggleFlyout()
            }

            Item {
                visible: !_entry.sep
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                opacity: _entry.on ? 1.0 : 0.4

                Item {
                    id: _mark
                    visible: _entry.checkable
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? Settings.fontSize : 0
                    height: Settings.fontSize

                    ShellText {
                        anchors.centerIn: parent
                        visible: _entry.btnType === 1 && _entry.checked
                        text: "󰄬"
                        color: Theme.accent
                        font.pixelSize: Settings.fontSize
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        visible: _entry.btnType === 2
                        width: 8; height: 8; radius: 4
                        antialiasing: true
                        color: _entry.checked ? Theme.accent : "transparent"
                        border.width: _entry.checked ? 0 : 1
                        border.color: Theme.withAlpha(Theme.subtext, 0.5)
                    }
                }

                IconImage {
                    id: _icon
                    visible: !_entry.checkable && _entry.iconSrc !== "" && status === Image.Ready
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: Settings.fontSize + 4
                    source: _entry.iconSrc
                    asynchronous: true
                }

                ShellText {
                    anchors.left: _entry.checkable ? _mark.right : _icon.visible ? _icon.right : parent.left
                    anchors.leftMargin: (_entry.checkable || _icon.visible) ? 8 : 0
                    anchors.right: _arrow.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: _entry.label
                    color: Theme.text
                    font.pixelSize: Settings.fontSize
                    elide: Text.ElideRight
                }

                ShellText {
                    id: _arrow
                    visible: _entry.sub
                    width: visible ? implicitWidth : 0
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰅂"
                    color: Theme.withAlpha(Theme.subtext, 0.7)
                    font.pixelSize: Settings.fontSize
                }
            }

            Rectangle {
                id: _flyout
                // reparented to the window root: inside the clipped row Flickable the submenu would be scissored away
                parent: win.contentItem
                property bool opened: false
                property real _shift: opened ? 0 : (_rootLaneOverlay ? 0 : (_flip ? 5 : -5))
                property var _menuStack: []

                visible: opened || opacity > 0.001
                enabled: opened
                opacity: opened ? 1 : 0
                z: 10
                readonly property real _w: win.menuWidth + pad * 2
                readonly property int  pad: 6
                // The 5px entrance translation leaves a 4px gap at its closest point.
                readonly property int _cascadeGap: 9
                readonly property var _parentFlyout: _entry.ownerFlyout
                readonly property var _currentMenu: _menuStack.length > 0
                    ? _menuStack[_menuStack.length - 1] : null
                readonly property bool _canGoBack: _menuStack.length > 1 || _rootLaneOverlay
                // mapToItem() captures no dependencies, so a binding freezes at the pre-layout position; re-snap off everything that moves the row
                property point _origin: Qt.point(0, 0)
                readonly property real _originTick: card.x + card.y + _entry.y
                    + (_entry.ownerScroll ? _entry.ownerScroll.contentY : 0)
                    + (_entry.ownerFlyout ? _entry.ownerFlyout.x + _entry.ownerFlyout.y : 0)
                on_OriginTickChanged: if (_flyout.visible) _flyout._syncOrigin()
                function _syncOrigin(): void {
                    _flyout._origin = _entry.mapToItem(null, 0, 0)
                }
                readonly property var _ownerMenu: _entry.ownerFlyout
                    ? _entry.ownerFlyout : card
                readonly property real _rightX: _ownerMenu.x + _ownerMenu.width + _cascadeGap
                readonly property real _leftX: _ownerMenu.x - _w - _cascadeGap
                readonly property bool _rightFits: win._flyoutLaneFits(_flyout, _rightX)
                readonly property bool _leftFits: win._flyoutLaneFits(_flyout, _leftX)
                readonly property bool _needsDrillIn: !_rightFits && !_leftFits
                    && _entry.ownerFlyout !== null
                readonly property bool _rootLaneOverlay: !_rightFits && !_leftFits
                    && _entry.ownerFlyout === null
                readonly property bool _adaptiveExpansion: _needsDrillIn || _rootLaneOverlay
                readonly property bool _flip: !_rightFits && _leftFits
                readonly property real _panelH: Math.min(_subCol.implicitHeight + pad * 2, Math.max(48, win.height - 8))
                readonly property real _targetY: Math.max(4 - _origin.y, Math.min(-pad, win.height - 4 - _origin.y - _panelH))
                readonly property real _rootOverlayY: Math.max(4, Math.min(card.y, win.height - 4 - _panelH))
                x: _rootLaneOverlay ? card.x : (_flip ? _leftX : _rightX)
                y: _rootLaneOverlay ? _rootOverlayY : _origin.y + _targetY
                width:  _w
                height: _panelH
                radius: Math.min(Theme.surfaceRadius, height / 2)
                antialiasing: true
                color: Theme.popup
                transform: Translate { x: _flyout._shift }

                OutlineBorder {
                    radius: _flyout.radius
                    outlineColor: Theme.outline
                }

                Disclosure on opacity { expanded: _flyout.opened; enterEasing: Easing.OutCubic }
                Disclosure on _shift { expanded: _flyout.opened }

                function _prepareToOpen(): void {
                    _menuStack = [_entry.modelData]
                    _subScroll.contentY = 0
                }
                function _drillInto(menu): void {
                    if (!opened || menu === null || menu === undefined) return
                    _menuStack = _menuStack.concat([menu])
                    _subScroll.contentY = 0
                    win._emitMenuSignal(menu, "opened", "sendOpened")
                }
                function _goBack(): void {
                    if (_menuStack.length === 1 && _rootLaneOverlay) {
                        _flyout.opened = false
                        return
                    }
                    if (!_canGoBack) return
                    const menu = _currentMenu
                    win._emitMenuSignal(menu, "closed", "sendClosed")
                    _menuStack = _menuStack.slice(0, -1)
                    _subScroll.contentY = 0
                }
                function _closeDrillMenus(): void {
                    for (let i = _menuStack.length - 1; i >= 0; i--)
                        win._emitMenuSignal(_menuStack[i], "closed", "sendClosed")
                }

                onOpenedChanged: {
                    if (!_entry.sub) return
                    if (opened) {
                        _flyout._syncOrigin()
                        win._emitMenuSignal(_flyout._currentMenu, "opened", "sendOpened")
                    } else {
                        _flyout._closeDrillMenus()
                    }
                }
                onVisibleChanged: if (!visible && !opened) _menuStack = []
                Component.onDestruction: if (_entry.sub && _flyout.opened) _flyout._closeDrillMenus()

                HoverHandler {
                    id: _flyHover
                    blocking: _flyout._rootLaneOverlay
                }

                Timer {
                    id: _flyClose
                    interval: 180
                    onTriggered: if (!_rowHover.hovered && !_flyHover.hovered) _entry.closeFlyout()
                }
                Connections {
                    target: _flyHover
                    function onHoveredChanged() { if (!_flyHover.hovered) _flyClose.restart() }
                }
                Connections {
                    target: _rowHover
                    function onHoveredChanged() { if (!_rowHover.hovered && _flyout.opened) _flyClose.restart() }
                }

                ShellFlickable {
                    id: _subScroll
                    x: _flyout.pad; y: _flyout.pad
                    width: win.menuWidth
                    height: Math.max(0, _flyout.height - _flyout.pad * 2)
                    contentWidth: width
                    contentHeight: _subCol.implicitHeight
                    interactive: contentHeight > height

                    Column {
                        id: _subCol
                        width: win.menuWidth
                        spacing: 1

                        Item {
                            visible: _flyout._canGoBack
                            width: win.menuWidth
                            height: visible ? win.menuRowHeight : 0

                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radiusControl
                                antialiasing: true
                                color: _backHover.hovered
                                    ? Theme.withAlpha(Theme.menuHover, 0.08) : "transparent"
                                ColorFade on color {}
                            }

                            ShellText {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰅁"
                                color: Theme.withAlpha(Theme.subtext, 0.7)
                                font.pixelSize: Settings.fontSize
                            }
                            ShellText {
                                anchors.left: parent.left
                                anchors.leftMargin: 28
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Back")
                                color: Theme.text
                                font.pixelSize: Settings.fontSize
                                elide: Text.ElideRight
                            }

                            HoverHandler {
                                id: _backHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: _flyout._goBack()
                            }
                        }

                        QsMenuOpener {
                            id: _laneOpener
                            menu: _flyout._currentMenu
                        }

                        Repeater {
                            // hold the delegates through the close fade, then release the nested branch while the flyout is hidden
                            model: _flyout.opened || _flyout.opacity > 0.001
                                ? _laneOpener.children : []
                            delegate: _rowDelegate
                            onItemAdded: (index, item) => {
                                item.ownerFlyout = _flyout
                                item.ownerScroll = _subScroll
                                item.menuDepth = _entry.menuDepth + _flyout._menuStack.length
                            }
                        }
                    }
                }

                ListEdgeLines {
                    anchors.fill: _subScroll
                    visible: _subScroll.interactive
                    list: _subScroll
                }
            }
        }
    }

    PopupShadow { card: card }

    FloatingPopupCard {
        id: card
        win: win
        open: TrayMenuState.open
        anchorX: TrayMenuState.effectiveAnchorX
        barBottom: TrayMenuState.barBottom

        readonly property int pad: 6
        readonly property real _maxContentH: Math.max(48, win.height - _edgeY - pad * 2 - 8)

        width:  win.menuWidth + pad * 2
        height: Math.min(_col.implicitHeight, _maxContentH) + pad * 2

        Connections {
            target: TrayMenuState
            function onOpenChanged() { if (TrayMenuState.open) card.forceActiveFocus() }
        }
        Component.onCompleted: if (TrayMenuState.open) card.forceActiveFocus()

        ShellFlickable {
            id: _scroll
            x: card.pad; y: card.pad
            width: win.menuWidth
            height: Math.max(0, card.height - card.pad * 2)
            contentWidth: width
            contentHeight: _col.implicitHeight
            interactive: contentHeight > height

            Column {
                id: _col
                width: win.menuWidth
                spacing: 1

                Repeater {
                    model: _opener.children
                    delegate: _rowDelegate
                    onItemAdded: (index, item) => item.ownerScroll = _scroll
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
