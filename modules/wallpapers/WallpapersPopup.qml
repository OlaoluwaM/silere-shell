pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

// A grid picker over Wallpapers.entries, dormant unless Wallpapers.available. Same
// centered-overlay shape as KeybindsPopup for the same reason: this is IPC-triggered with
// no bar pill to anchor off, and a picker reads better as a dialog than pinned to an edge.
PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property string _output: Compositor.monitorName(win.screen)

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && WallpapersPopupState.open) WallpapersPopupState.close()
        }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-wallpapers"
    WlrLayershell.keyboardFocus: WallpapersPopupState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: WallpapersPopupState.open || card.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: WallpapersPopupState.open
        onActivated: {
            if (card.filterVisible) card.hideFilter()
            else WallpapersPopupState.close()
        }
    }

    Shortcut {
        sequence: "Ctrl+F"
        context: Qt.ApplicationShortcut
        enabled: WallpapersPopupState.open
        onActivated: card.showFilter()
    }

    OutsideTapGuard {
        id: _tapGuard
        open: WallpapersPopupState.open
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: WallpapersPopupState.open ? _fillArea : null }

    TapHandler {
        id: _dismiss
        enabled: WallpapersPopupState.open && card.scaleAmt > 0.95
        onTapped: {
            if (_tapGuard.ignoring) return
            const p = _dismiss.point.position
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                WallpapersPopupState.close()
        }
    }

    Loader {
        anchors.fill: card
        z: -1
        active: (card.open || card.opacity > 0.001) && ShellSettings.barShadow
        opacity: card.opacity
        sourceComponent: FloatingShadow { radius: card.radius; atBottom: false }
    }

    // quiet text action: invisible at rest, a hover step reveals fill + a hairline
    // border per Theme.controlFill's solid-on-glass doctrine
    component RandomAction: Item {
        id: _ra
        signal triggered()
        readonly property bool hovered: _raHover.hovered

        implicitWidth: _raText.implicitWidth + 16
        implicitHeight: Metrics.rowHeightFor(22)
        width: implicitWidth
        height: implicitHeight

        HoverHandler { id: _raHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: _ra.triggered() }

        Rectangle {
            id: _raSurface
            anchors.fill: parent
            radius: Theme.radiusInline
            antialiasing: true
            color: _ra.hovered ? Theme.controlFill(Theme.text, 0.06) : "transparent"
            ColorFade on color {}

            OutlineBorder {
                radius: _raSurface.radius
                outlineColor: _ra.hovered ? Theme.menuControlLine : "transparent"
                ColorFade on outlineColor {}
            }
        }

        ShellText {
            id: _raText
            anchors.centerIn: parent
            text: "Random"
            color: _ra.hovered ? Theme.withAlpha(Theme.text, 0.82) : Theme.withAlpha(Theme.subtext, 0.70)
            font.pixelSize: Settings.fontCaption
            font.weight: Font.DemiBold
            ColorFade on color {}
        }
    }

    Rectangle {
        id: card

        readonly property bool open: WallpapersPopupState.open
        property bool filterVisible: false
        // set from _queryDebounce, not bound to _filter.text: swapping the JS-array model
        // tears down every visible delegate (reuseItems is off) and restarts its async
        // decode, so the grid pays one reset per typing pause, not one per keystroke
        property string query: ""
        readonly property var filtered: {
            const q = card.query
            const src = Wallpapers.entries
            if (q.length === 0) return src
            const out = []
            for (let i = 0; i < src.length; i++) {
                if (src[i].nameLower.indexOf(q) >= 0) out.push(src[i])
            }
            return out
        }
        // every path that changes the model lands here: the async scan on open, each filter
        // pause, a cleared query. Reassigning a JS-array model drops GridView's current
        // item, so without this Enter silently does nothing until an arrow key is pressed --
        // keeping the top entry selected is the launcher behavior the field imitates.
        onFilteredChanged: {
            // through -1 first: writing an unchanged index (commonly 0) early-outs in the
            // setter, and the model reset that follows would then drop currentItem anyway
            _grid.currentIndex = -1
            _grid.currentIndex = filtered.length > 0 ? 0 : -1
        }

        Timer {
            id: _queryDebounce
            interval: 90
            onTriggered: card.query = _filter.text.trim().toLowerCase()
        }

        function showFilter(): void {
            card.filterVisible = true
            Qt.callLater(() => _filter.forceActiveFocus())
        }
        function hideFilter(): void {
            card.filterVisible = false
            _filter.text = ""
            // Escape restores the full grid now, not a debounce interval later
            _queryDebounce.stop()
            card.query = ""
            _grid.forceActiveFocus()
        }
        function applyCurrent(): void {
            const item = _grid.currentItem
            if (item) Wallpapers.apply(item.modelData.path)
        }
        function pickRandom(): void {
            const list = card.filtered
            if (list.length === 0) return
            const idx = Math.floor(Math.random() * list.length)
            Wallpapers.apply(list[idx].path)
            _grid.currentIndex = idx
            _grid.positionViewAtIndex(idx, GridView.Contain)
        }

        readonly property int pad: 16
        readonly property int _cols: 4
        readonly property int _gap: 10
        readonly property int _headerH: Metrics.rowHeightFor(28)
        readonly property int _gridY: card.pad + card._headerH + 10
        readonly property int _cellW: Math.floor((card.width - card.pad * 2) / card._cols)
        readonly property int _cellH: Math.round(card._cellW * 10 / 16)

        anchors.centerIn: parent
        width:  Math.round(Math.max(360, Math.min(620, win.width - 96)))
        height: Math.round(Math.min(win.height - 64, card._gridY + 2 * card._cellH + card.pad))
        radius: Theme.radiusPanel
        antialiasing: true
        color: Theme.popup

        property real scaleAmt: Motion.popScaleFrom
        opacity: 0
        transformOrigin: Item.Center
        transform: Scale {
            origin.x: card.width / 2
            origin.y: card.height / 2
            xScale: card.scaleAmt
            yScale: card.scaleAmt
        }
        layer.enabled: !ShellSettings.reduceMotion && opacity > 0.001
            && (card.scaleAmt < 0.999 || !card.open)

        property bool _transitionReady: false

        function _snapOpen(): void {
            _enterAnim.stop(); _exitAnim.stop()
            card.scaleAmt = 1.0
            card.opacity = 1.0
        }
        function _snapClosed(): void {
            _enterAnim.stop(); _exitAnim.stop()
            card.scaleAmt = Motion.popScaleFrom
            card.opacity = 0.0
        }
        function _startOpen(): void {
            _exitAnim.stop()
            if (ShellSettings.reduceMotion) card._snapOpen()
            else _enterAnim.restart()
        }
        function _startClose(): void {
            _enterAnim.stop()
            if (ShellSettings.reduceMotion) card._snapClosed()
            else _exitAnim.restart()
        }

        onOpenChanged: if (card._transitionReady) { if (open) card._startOpen(); else card._startClose() }

        Component.onCompleted: {
            card._snapClosed()
            if (card.open) {
                Wallpapers.rescan()
                _grid.forceActiveFocus()
            }
            Qt.callLater(function() {
                card._transitionReady = true
                if (card.open) card._startOpen()
            })
        }

        ParallelAnimation {
            id: _enterAnim
            NumberAnimation { target: card; property: "scaleAmt"; to: 1.0; duration: Motion.popIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
            NumberAnimation { target: card; property: "opacity";  to: 1.0; duration: Motion.popInFade; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            id: _exitAnim
            NumberAnimation { target: card; property: "scaleAmt"; to: Motion.popScaleFrom; duration: Motion.popOut; easing.type: Easing.InCubic }
            NumberAnimation { target: card; property: "opacity";  to: 0.0; duration: Motion.popOutFade; easing.type: Easing.InCubic }
        }

        Connections {
            target: ShellSettings
            function onReduceMotionChanged() {
                if (!ShellSettings.reduceMotion) return
                if (card.open) card._snapOpen(); else card._snapClosed()
            }
        }

        // a directory scan is not free (a `find` process) -- only pay for it when the
        // popup is actually about to be looked at, same reasoning as Keybinds.reload()
        Connections {
            target: WallpapersPopupState
            function onOpenChanged() {
                if (!WallpapersPopupState.open) return
                Wallpapers.rescan()
                card.filterVisible = false
                _filter.text = ""
                _grid.forceActiveFocus()
            }
        }

        OutlineBorder {
            radius: card.radius
            outlineColor: Theme.outline
        }

        Item {
            id: _headerWrap
            x: card.pad
            y: card.pad
            width: card.width - card.pad * 2
            height: card._headerH

            Row {
                id: _titleGroup
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                ShellText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wallpapers"
                    color: Theme.withAlpha(Theme.mix(Theme.menuTextMuted, Theme.accent, 0.10), 0.84)
                    font.pixelSize: Settings.fontCaption
                    font.letterSpacing: 0.65
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                }
                ShellText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "· " + (card.query.length > 0
                        ? card.filtered.length + "/" + Wallpapers.entries.length
                        : Wallpapers.entries.length)
                    color: Theme.withAlpha(Theme.subtext, 0.62)
                    font.pixelSize: Settings.fontCaption
                }
            }

            RandomAction {
                id: _randomAction
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onTriggered: card.pickRandom()
            }

            Rectangle {
                id: _filterField
                visible: card.filterVisible
                // right-anchored with its own width, never left-anchored to _titleGroup:
                // the count text there re-sizes with the match tally, and a field whose
                // left edge tracks it would shift under the cursor mid-typing. The floor
                // keeps the input usable when title + action squeeze it at scaled type.
                width: Math.max(80, Math.min(220,
                    _headerWrap.width - _titleGroup.width - _randomAction.width - 20))
                anchors.right: _randomAction.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                height: Metrics.rowHeightFor(26)
                radius: Theme.radiusField
                antialiasing: true
                color: Theme.controlFill(Theme.text, _filter.activeFocus ? 0.08 : 0.05)
                ColorFade on color {}

                OutlineBorder {
                    radius: _filterField.radius
                    outlineColor: _filter.activeFocus
                        ? Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)
                        : Theme.menuControlLine
                    ColorFade on outlineColor {}
                }

                ShellText {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍉"
                    color: Theme.withAlpha(Theme.subtext, 0.62)
                    font.pixelSize: Settings.fontCaption
                }

                TextInput {
                    id: _filter
                    anchors.left: parent.left
                    anchors.leftMargin: 28
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text
                    selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontCaption
                    renderType: Text.NativeRendering
                    clip: true

                    onTextChanged: _queryDebounce.restart()

                    // arrows/Enter always drive the grid, even while this field holds
                    // focus for filtering -- typing at rest does nothing else here
                    Keys.onUpPressed: (event) => { _grid.moveCurrentIndexUp(); event.accepted = true }
                    Keys.onDownPressed: (event) => { _grid.moveCurrentIndexDown(); event.accepted = true }
                    Keys.onLeftPressed: (event) => { _grid.moveCurrentIndexLeft(); event.accepted = true }
                    Keys.onRightPressed: (event) => { _grid.moveCurrentIndexRight(); event.accepted = true }
                    Keys.onReturnPressed: (event) => { card.applyCurrent(); event.accepted = true }
                    Keys.onEnterPressed: (event) => { card.applyCurrent(); event.accepted = true }

                    ShellText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: _filter.text.length === 0
                        text: "Filter wallpapers"
                        color: Theme.withAlpha(Theme.subtext, 0.45)
                        font.pixelSize: Settings.fontCaption
                    }
                }
            }
        }

        ShellGridView {
            id: _grid
            x: card.pad
            y: card._gridY
            width: card.width - card.pad * 2
            height: Math.max(0, card.height - card._gridY - card.pad)
            cellWidth: card._cellW
            cellHeight: card._cellH
            model: card.filtered
            keyNavigationEnabled: true
            highlightFollowsCurrentItem: true
            // KeybindsPopup tunes its cheap text list to 240; each delegate here holds a
            // decoded thumbnail, so the off-screen decode window gets about one row
            cacheBuffer: card._cellH

            Keys.onReturnPressed: (event) => { card.applyCurrent(); event.accepted = true }
            Keys.onEnterPressed: (event) => { card.applyCurrent(); event.accepted = true }

            delegate: Item {
                id: _tile
                required property var modelData
                required property int index

                readonly property bool current: modelData.path === ShellSettings.wallpaperLast
                readonly property bool kbFocused: GridView.isCurrentItem
                readonly property bool hovered: _tileHover.hovered

                width: _grid.cellWidth
                height: _grid.cellHeight

                Rectangle {
                    id: _tileSurface
                    anchors.fill: parent
                    anchors.margins: card._gap / 2
                    radius: Theme.radiusInline
                    antialiasing: true
                    clip: true
                    color: Theme.controlFill(Theme.text, 0.04)

                    HoverHandler { id: _tileHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            _grid.currentIndex = _tile.index
                            Wallpapers.apply(_tile.modelData.path)
                        }
                    }

                    Image {
                        id: _thumb
                        anchors.fill: parent
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        // Qt's pixmap cache outlives the delegate AND the popup: browsing
                        // a large directory once would pin every thumbnail for the life
                        // of the shell process
                        cache: false
                        source: IconResolver.localSource(_tile.modelData.path)
                        // decode size comes from the layout constants, not the live item
                        // width: binding to _tileSurface re-evaluates as layout settles
                        // (0 -> real), and every sourceSize change forces a fresh decode
                        // of a full-resolution file per tile
                        sourceSize.width: (card._cellW - card._gap) * 2
                        sourceSize.height: (card._cellH - card._gap) * 2
                    }

                    // a file deleted or unreadable between scan and render would otherwise
                    // leave a tile indistinguishable from one still decoding -- same
                    // Image.Error gate as NotificationCard and MediaCard
                    ShellText {
                        anchors.centerIn: parent
                        visible: _thumb.status === Image.Error
                        text: "󰋩"
                        color: Theme.withAlpha(Theme.subtext, 0.6)
                        font.pixelSize: Settings.fontSize
                    }

                    Item {
                        anchors.fill: parent
                        visible: _tile.hovered || _tile.kbFocused
                        clip: true

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: Math.round(parent.height * 0.44)
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: Theme.withAlpha("#000000", 0.58) }
                            }
                        }

                        ShellText {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            elide: Text.ElideRight
                            text: _tile.modelData.name
                            color: "#ffffff"
                            font.pixelSize: Settings.fontMicro
                            font.weight: Font.DemiBold
                        }
                    }

                    OutlineBorder {
                        radius: _tileSurface.radius
                        outlineColor: Theme.outline
                    }

                    OutlineBorder {
                        radius: _tileSurface.radius
                        outlineWidth: 2
                        outlineColor: _tile.current ? Theme.controlLineActive(Theme.accent) : "transparent"
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: 3
                        OutlineBorder {
                            radius: Math.max(0, _tileSurface.radius - 3)
                            outlineWidth: 2
                            outlineColor: _tile.kbFocused
                                ? Theme.withAlpha(Theme.text, Theme.focusRingAlpha) : "transparent"
                        }
                    }

                    Item {
                        visible: _tile.current
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 6
                        width: 12
                        height: 12

                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            radius: 6
                            color: Theme.withAlpha(Theme.popup, 1.0)
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: 3
                            color: Theme.accent
                        }
                    }
                }
            }
        }

        Column {
            anchors.centerIn: _grid
            // the scanning gate matters on the very first open: state still holds its
            // pre-scan "unconfigured" default until the find lands, and flashing that
            // message on a configured machine would be a lie
            visible: !Wallpapers.scanning && Wallpapers.state !== "ok"
            spacing: 4

            ShellText {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                color: Theme.withAlpha(Theme.subtext, 0.7)
                font.pixelSize: Settings.fontSize
                text: Wallpapers.state === "unconfigured" ? "No wallpaper directory configured"
                    : Wallpapers.state === "missing" ? "Can't read " + ShellSettings.wallpapersDir
                    : "No images found in " + ShellSettings.wallpapersDir
            }
            ShellText {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                color: Theme.withAlpha(Theme.subtext, 0.5)
                font.pixelSize: Settings.fontCaption
                text: Wallpapers.state === "unconfigured" ? "Set wallpapersDir in settings.json to enable the picker"
                    : Wallpapers.state === "missing" ? "That path is not a readable directory"
                    : "Looking for png, jpg, jpeg, webp, avif, bmp files"
            }
        }

        ShellText {
            anchors.centerIn: _grid
            visible: Wallpapers.state === "ok" && card.filtered.length === 0
            text: "No wallpapers match"
            color: Theme.withAlpha(Theme.subtext, 0.5)
            font.pixelSize: Settings.fontSize
        }

        ListEdgeLines {
            anchors.fill: _grid
            visible: _grid.contentHeight > _grid.height
            list: _grid
        }
    }
}
