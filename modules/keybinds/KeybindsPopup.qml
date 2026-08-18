pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

// A searchable reference card for Keybinds.entries, dormant unless Keybinds.available.
// Unlike the bar-anchored popups (Calendar/Menu/Tray*/QuickActions, all built on
// FloatingPopupCard), this one is triggered purely by IPC -- there is no bar pill to
// anchor off, and a reference card reads better centered like a dialog than pinned to
// an edge. So the card below is its own light Rectangle with a center-scale open/close
// instead of FloatingPopupCard's edge-slide, reusing the same Motion tokens.
PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property string _output: Compositor.monitorName(win.screen)

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && KeybindsPopupState.open) KeybindsPopupState.close()
        }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-keybinds"
    WlrLayershell.keyboardFocus: KeybindsPopupState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: KeybindsPopupState.open || card.opacity > 0.001

    anchors { top: true; left: true; right: true; bottom: true }

    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        enabled: KeybindsPopupState.open
        onActivated: KeybindsPopupState.close()
    }

    OutsideTapGuard {
        id: _tapGuard
        open: KeybindsPopupState.open
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: KeybindsPopupState.open ? _fillArea : null }

    TapHandler {
        id: _dismiss
        enabled: KeybindsPopupState.open && card.scaleAmt > 0.95
        onTapped: {
            if (_tapGuard.ignoring) return
            const p = _dismiss.point.position
            if (p.x < card.x || p.x > card.x + card.width ||
                p.y < card.y || p.y > card.y + card.height)
                KeybindsPopupState.close()
        }
    }

    Loader {
        anchors.fill: card
        z: -1
        active: (card.open || card.opacity > 0.001) && ShellSettings.barShadow
        opacity: card.opacity
        sourceComponent: FloatingShadow { radius: card.radius; atBottom: false }
    }

    component GroupHeader: Item {
        id: _hdr
        property string label: ""
        property bool first: false
        readonly property int _topGap: first ? 2 : Theme.gapSection
        readonly property int _botGap: 6

        ShellText {
            id: _hdrText
            x: 4
            y: _hdr._topGap
            width: parent.width - 8
            text: _hdr.label
            elide: Text.ElideRight
            color: Theme.withAlpha(Theme.mix(Theme.menuTextMuted, Theme.accent, 0.10), 0.84)
            font.pixelSize: Settings.fontCaption
            font.letterSpacing: 0.65
            font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase
        }

        implicitHeight: _hdr._topGap + _hdrText.implicitHeight + _hdr._botGap
    }

    // solid-on-glass per Theme.controlFill's own doctrine: this card paints Theme.popup
    // (glass when ShellSettings.glassSurfaces is on), so a chip needs an opaque step of
    // its own rather than the translucent Theme.menuControl wash a chip would reach for
    // on an already-opaque pane
    component KeyChip: Rectangle {
        id: _chip
        property string label: ""

        implicitWidth: _chipText.implicitWidth + 14
        implicitHeight: Metrics.rowHeightFor(20)
        width: implicitWidth
        height: implicitHeight
        radius: Theme.radiusField
        antialiasing: true
        color: Theme.controlFill(Theme.text, 0.06)

        OutlineBorder {
            radius: _chip.radius
            outlineColor: Theme.menuControlLine
        }

        ShellText {
            id: _chipText
            anchors.centerIn: parent
            text: _chip.label
            color: Theme.withAlpha(Theme.text, 0.86)
            font.pixelSize: Settings.fontMicro
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        id: card

        readonly property bool open: KeybindsPopupState.open
        readonly property string query: _search.text.trim().toLowerCase()
        readonly property var filtered: {
            const q = card.query
            const src = Keybinds.entries
            if (q.length === 0) return src
            const out = []
            for (let i = 0; i < src.length; i++) {
                const e = src[i]
                if (e.keys.toLowerCase().indexOf(q) >= 0
                        || e.desc.toLowerCase().indexOf(q) >= 0
                        || e.group.toLowerCase().indexOf(q) >= 0)
                    out.push(e)
            }
            return out
        }

        anchors.centerIn: parent
        width:  Math.round(Math.max(280, Math.min(560, win.width - 96)))
        height: Math.round(Math.max(320, Math.min(640, win.height - 96)))
        radius: Theme.radiusPanel
        antialiasing: true
        color: Theme.popup

        readonly property int pad: 16

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
            if (card.open) { Keybinds.reload(); _search.forceActiveFocus() }
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

        // the file is static per system generation (see Keybinds.qml), so this reload is
        // insurance for a same-session rebuild landing while the shell is already up, not
        // a substitute for a watcher
        Connections {
            target: KeybindsPopupState
            function onOpenChanged() {
                if (!KeybindsPopupState.open) return
                Keybinds.reload()
                _search.text = ""
                _search.forceActiveFocus()
            }
        }
        OutlineBorder {
            radius: card.radius
            outlineColor: Theme.outline
        }

        Item {
            id: _searchWrap
            x: card.pad
            y: card.pad
            width: card.width - card.pad * 2
            height: Metrics.rowHeightFor(36)

            Rectangle {
                id: _searchField
                anchors.fill: parent
                radius: Theme.radiusField
                antialiasing: true
                color: Theme.controlFill(Theme.text, _search.activeFocus ? 0.08 : 0.05)
                ColorFade on color {}

                OutlineBorder {
                    radius: _searchField.radius
                    outlineColor: _search.activeFocus
                        ? Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)
                        : Theme.menuControlLine
                    ColorFade on outlineColor {}
                }

                ShellText {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍉"
                    color: Theme.withAlpha(Theme.subtext, 0.62)
                    font.pixelSize: Settings.fontSize
                }

                TextInput {
                    id: _search
                    anchors.left: parent.left
                    anchors.leftMargin: 34
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text
                    selectionColor: Theme.withAlpha(Theme.accent, 0.4)
                    font.family: Settings.font
                    font.pixelSize: Settings.fontSize
                    renderType: Text.NativeRendering
                    clip: true
                    // first Escape clears an active filter; a second (now-empty) press
                    // falls through unaccepted to the window's own Escape Shortcut above
                    Keys.onEscapePressed: (event) => {
                        if (_search.text.length > 0) { _search.text = ""; event.accepted = true }
                    }

                    ShellText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: _search.text.length === 0
                        text: "Search keybindings"
                        color: Theme.withAlpha(Theme.subtext, 0.45)
                        font.pixelSize: Settings.fontSize
                    }
                }
            }
        }

        ShellListView {
            id: _list
            x: card.pad
            y: _searchWrap.y + _searchWrap.height + 10
            width: card.width - card.pad * 2
            height: Math.max(0, card.height - y - card.pad)
            spacing: 2
            cacheBuffer: 240
            model: card.filtered

            delegate: Item {
                id: _row
                required property var modelData
                required property int index

                readonly property bool _showHeader: index === 0
                    || modelData.group !== card.filtered[index - 1].group

                width: _list.width
                height: _header.height + _chordRow.height

                GroupHeader {
                    id: _header
                    x: 0; y: 0
                    width: parent.width
                    visible: _row._showHeader
                    height: visible ? implicitHeight : 0
                    label: _row.modelData.group
                    first: _row.index === 0
                }

                Item {
                    id: _chordRow
                    x: 0
                    y: _header.height
                    width: parent.width
                    height: Metrics.rowHeightFor(30)

                    ShellText {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.right: _chips.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: _row.modelData.desc
                        elide: Text.ElideRight
                        color: Theme.text
                        font.pixelSize: Settings.fontSize
                    }

                    Row {
                        id: _chips
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Repeater {
                            model: _row.modelData.keys.split(" + ")
                            delegate: KeyChip {
                                required property string modelData
                                label: modelData
                            }
                        }
                    }
                }
            }
        }

        ShellText {
            anchors.centerIn: _list
            visible: card.filtered.length === 0
            text: "No matching keybindings"
            color: Theme.withAlpha(Theme.subtext, 0.5)
            font.pixelSize: Settings.fontSize
        }

        ListEdgeLines {
            anchors.fill: _list
            visible: _list.contentHeight > _list.height
            list: _list
        }
    }
}
