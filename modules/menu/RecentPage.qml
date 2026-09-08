pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import "../../config"
import "../../services"
import "../common"
import "controls"

PageShell {
    id: root

    required property int viewportHeight

    implicitHeight: viewportHeight
    onPageShown: root._touchNow()

    property bool _clearing: false
    property int _timeTick: 0
    property real _nowMs: 0
    property real _todayStartMs: 0

    // three from one app in one day is where a repeat stops reading as separate events
    readonly property int foldAt: 3

    HistoryGrouping {
        id: _historyGrouping
        model: Notifications.historyModel
        foldAt: root.foldAt
    }

    function _touchNow(): void {
        const nowMs = Date.now()
        const now = new Date(nowMs)
        root._nowMs = nowMs
        root._todayStartMs = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        root._timeTick++
    }

    Component.onCompleted: root._touchNow()

    Connections {
        target: ShellSettings
        function onClock12hChanged() { root._touchNow() }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.active && MenuState.open && !Idle.isIdle
        onTriggered: root._touchNow()
    }

    onPageHidden: {
        _clearButton.disarm()
        // the refold happens under the page's own exit fade, so it snaps like a model change
        root._holdHeights()
        _historyGrouping.reset()
    }

    function formatTime(ms): string {
        const nowMs = root._nowMs > 0 ? root._nowMs : Date.now()
        const value = Number(ms || nowMs)
        const diff = Math.max(0, nowMs - value)
        if (diff < 60000)   return "now"
        if (diff < 3600000) return Math.floor(diff / 60000) + "m"

        const d = new Date(value)
        const today = root._todayStartMs > 0 ? root._todayStartMs : nowMs
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        // whole days, not milliseconds: a DST day is 23 or 25 hours long, and the raw
        // gap then lands one bucket early — two sections both headed Yesterday
        const days = Math.round((today - day) / 86400000)
        if (days <= 0 && diff < 86400000) return Math.floor(diff / 3600000) + "h"
        // the section header already carries the day, so an older entry only owes a clock
        // qt only counts 12-hour when AP shares the format string
        return Qt.formatDateTime(d, ShellSettings.clock12h ? "h:mm ap" : "HH:mm")
    }

    // a row's height must not animate on a model change: the list lays the rows below
    // out from the height it sees at that moment and its displaced transition carries
    // them there, so a height still in flight leaves them overlapping or adrift once it
    // lands. Only the user's own fold and unfold animate. Raised on the about-to signals
    // because delegate indexes, and everything derived from them, update inside the
    // change itself, before the count moves; dropped after the synchronous pass, before
    // the list gets to lay out
    property bool _settling: false

    function _holdHeights(): void {
        root._settling = true
        Qt.callLater(() => root._settling = false)
    }

    Connections {
        target: _historyGrouping
        function onModelAboutToChange() { root._holdHeights() }
    }

    function sectionLabel(ms): string {
        const nowMs = root._nowMs > 0 ? root._nowMs : Date.now()
        const value = Number(ms || nowMs)
        const d = new Date(value)
        const today = root._todayStartMs > 0 ? root._todayStartMs : nowMs
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        const days = Math.round((today - day) / 86400000)
        if (days <= 0) return "Today"
        if (days === 1) return "Yesterday"
        if (days < 7) return Qt.formatDateTime(d, "dddd")
        // past a week the weekday alone stops meaning anything, so the date takes over;
        // the year only once it is not this one
        return Qt.formatDateTime(d, d.getFullYear() === new Date(nowMs).getFullYear()
            ? "ddd MMM d" : "MMM d, yyyy")
    }

    function clearAll(): void {
        if (_clearing || Notifications.historyCount === 0) return
        if (ShellSettings.reduceMotion) {
            Notifications.clearHistory()
            return
        }
        _clearing = true
        _clearAllAnimation.restart()
    }

    SequentialAnimation {
        id: _clearAllAnimation
        NumberAnimation {
            target: _historyList
            property: "opacity"
            to: 0
            duration: Motion.fast
            easing.type: Easing.InCubic
        }
        ScriptAction {
            script: {
                Notifications.clearHistory()
                _historyList.opacity = 1
                root._clearing = false
            }
        }
    }

    Item {
        id: _pageSurface
        width: parent.width
        height: root.viewportHeight

        Item {
            id: _header
            width: parent.width
            height: Metrics.rowHeightFor(38)

            ShellText {
                id: _headerTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1, Math.min(implicitWidth,
                    (_clearButton.visible ? _clearButton.x - 10 : _header.width)
                    - (_countChip.visible ? _countChip.width + 9 : 0)))
                text: "Notifications"
                color: Theme.text
                font.pixelSize: Settings.fontSize + 4
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Rectangle {
                id: _countChip
                anchors.left: _headerTitle.right
                anchors.leftMargin: 9
                anchors.verticalCenter: _headerTitle.verticalCenter
                visible: Notifications.hasHistory
                width:  Math.max(18, _countTxt.implicitWidth + 12)
                height: 18
                radius: 9
                antialiasing: true
                color: Theme.withAlpha(Theme.subtext, 0.12)

                ShellText {
                    id: _countTxt
                    anchors.centerIn: parent
                    text: String(Notifications.historyCount)
                    color: Theme.withAlpha(Theme.text, 0.62)
                    font.pixelSize: Settings.fontMicro
                    font.weight: Font.DemiBold
                }
            }

            ConfirmButton {
                id: _clearButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Notifications.hasHistory
                glyph: "󰆴"
                label: "Clear"
                busy:  root._clearing
                onConfirmed: root.clearAll()
            }
        }

        Item {
            width: parent.width
            anchors.top: _header.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            visible: !Notifications.hasHistory

            Column {
                anchors.centerIn: parent
                spacing: 7

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 48
                    height: 48
                    radius: 24
                    antialiasing: true
                    color: Theme.withAlpha(Theme.subtext, 0.07)

                    OutlineBorder {
                        radius: 24
                        outlineColor: Theme.menuCardBorder
                    }

                    ShellText {
                        anchors.centerIn: parent
                        text: "󱇦"
                        color: Theme.withAlpha(Theme.subtext, 0.34)
                        font.pixelSize: 24
                    }
                }

                Item { width: 1; height: 2 }

                ShellText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "All caught up"
                    color: Theme.withAlpha(Theme.text, 0.78)
                    font.pixelSize: Settings.fontSize + 1
                    font.weight: Font.Medium
                }

                ShellText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "New notifications will appear here"
                    color: Theme.withAlpha(Theme.subtext,
                        ShellSettings.highContrast ? 0.72 : 0.52)
                    font.pixelSize: Settings.fontCaption
                }
            }
        }

        ShellListView {
            id: _historyList
            anchors.top: _header.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            width: parent.width
            // runs of one app close up and days pull apart, so every gap is carried by the delegate
            spacing: 0
            visible: Notifications.hasHistory
            cacheBuffer: 240
            reuseItems: true
            model: Notifications.historyModel

            // clearAll runs its own fade over the whole list, so per-row motion there
            // would animate every delegate at once behind an already-invisible list
            displaced: Transition {
                enabled: !root._clearing
                NumberAnimation { property: "y"; duration: Motion.normal; easing.type: Easing.OutCubic }
            }
            add: Transition {
                enabled: !root._clearing
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.fast }
            }
            // the row collapses as it fades, on the same curve the rows below use to close,
            // so their edge follows its edge and nothing is ever drawn across leaving text.
            // _leaveK scales the height binding rather than the transition writing height,
            // which would sever the binding for the row's next life
            remove: Transition {
                enabled: !root._clearing
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: Motion.normal; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "_leaveK"; to: 0; duration: Motion.normal; easing.type: Easing.OutCubic }
                }
            }
            removeDisplaced: Transition {
                enabled: !root._clearing
                NumberAnimation { property: "y"; duration: Motion.normal; easing.type: Easing.OutCubic }
            }

            delegate: Item {
                    id: _entry
                    // a ListModel delegate gets roles, not modelData; alias so the rest of the entry reads the same
                    required property var model
                    readonly property var modelData: model
                    required property int index

                    readonly property bool _critical: Number(modelData.urgency) === 2

                    // a row in its remove transition has index -1 and no neighbours, so anything
                    // read from the model would snap to a lone header mid-fade: a folded follower
                    // popping open, a stack dropping its peeks. The shape holds its last live frame
                    property var _shape: ({ first: true, section: true, header: true, length: 1, critical: false, open: false, key: "" })
                    Binding on _shape {
                        when: _entry.index >= 0
                        restoreMode: Binding.RestoreNone
                        value: {
                            return _historyGrouping.shapeAt(_entry.index)
                        }
                    }
                    readonly property bool _showSection: _shape.section
                    readonly property bool _showHeader: _shape.header

                    readonly property string _appIconSource: {
                        Notifications.entriesTick
                        return _entry._showHeader ? Notifications.appIconSource(
                            modelData.appIcon, modelData.desktopEntry, modelData.appName) : ""
                    }
                    readonly property string _appIconFallback: {
                        Notifications.entriesTick
                        return _entry._showHeader ? Notifications.entryIconSource(
                            modelData.desktopEntry, modelData.appName) : ""
                    }

                    readonly property string _runKey: _shape.key
                    readonly property int _runLength: _shape.length
                    readonly property bool _runCritical: _shape.critical
                    readonly property bool _stackable: _runLength >= root.foldAt
                    readonly property bool _runOpen: _shape.open
                    // the run's newest entry stands in for the rest while it is folded
                    readonly property bool _stacked: _showHeader && _stackable && !_runOpen
                    readonly property bool _folded: !_showHeader && _stackable && !_runOpen
                    readonly property int _peeks: _stacked ? Math.min(2, _runLength - 1) : 0

                    readonly property int _topPad: 11
                    readonly property int _sidePad: 14
                    readonly property int _peekStep: 6
                    readonly property int _peekInset: 8
                    readonly property int _rightGutter: _rightSlot.width + 10
                    readonly property int _firstLineHeight: _showHeader ? _metaRow.height : _summary.height
                    readonly property int _sectionHeight: _showSection ? 24 : 0
                    readonly property int _gapAbove: _shape.first ? 0 : _showSection ? 14 : 8
                    // summed from the parts rather than read off the Column: a positioner
                    // reports its new implicitHeight a frame late, after the list has already
                    // aimed the rows below at the old height, and they snap when the slide ends
                    readonly property int _cardHeight: Metrics.snap4Up(2 * _entry._topPad
                        + (_metaRow.visible ? _metaRow.height + _entryContent.spacing : 0)
                        + _summary.implicitHeight
                        + (_body.visible ? _entryContent.spacing + _body.implicitHeight : 0))
                    readonly property int _fullHeight: _gapAbove + _sectionHeight + _cardHeight
                    property bool _removing: false

                    property real _leaveK: 1
                    width: _historyList.width
                    // the peeks live below the card, so the row grows to keep the next one clear
                    height: (_folded ? 0 : _fullHeight + _peekStep * _peeks) * _leaveK
                    clip: true
                    // a folded follower still has a card's worth of handlers behind zero height
                    enabled: !_folded

                    // text lays out a frame after the delegate completes, so an ungated behaviour animates every row as it scrolls into view
                    property bool _heightReady: false
                    Timer { id: _heightArm; interval: 0; onTriggered: _entry._heightReady = true }
                    Component.onCompleted: _heightArm.start()
                    Component.onDestruction: _heightArm.stop()
                    ListView.onPooled: {
                        _heightArm.stop()
                        _entry._heightReady = false
                        _body.expanded = false
                        _entry._removing = false
                    }
                    ListView.onReused: {
                        // the remove transition pools the row faded out and collapsed
                        _entry.opacity = 1
                        _entry._leaveK = 1
                        _body.expanded = false
                        _entry._removing = false
                        _entry._heightReady = false
                        _heightArm.restart()
                    }
                    // a leaving row's height is driven by its transition; the behaviour would
                    // only chase it a frame behind
                    MotionBehavior on height {
                        gate: _entry._heightReady && !root._settling && _entry.index >= 0
                        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
                    }
                    // a third message folding the run would otherwise strand an expanded body
                    // on a card whose tap now opens the run and whose Less pill is gone
                    on_StackedChanged: if (_entry._stacked) _body.expanded = false
                    // and a follower folded by a third arrival would reopen already expanded
                    on_FoldedChanged: if (_entry._folded) _body.expanded = false

                    function _toggleExpand(): void {
                        if (root._clearing || _entry._removing || _entry._folded) return
                        if (_entry._stacked) _historyGrouping.setOpen(_entry._runKey, true)
                        else _body.toggle()
                    }

                    function removeSelf(): void {
                        if (_removing || root._clearing) return
                        const rowIndex = index
                        // persist immediately. A delegate-owned delay is lost if the user changes pages before its timer fires
                        _removing = true
                        // a folded stack is one card on screen; its × takes the run it stands for
                        if (_entry._stacked)
                            Notifications.removeRunFromHistory(rowIndex, _entry._runLength)
                        else
                            Notifications.removeFromHistory(rowIndex)
                    }

                    // an open run's header is a plain row, so Clear all cannot come off the
                    // folded branch above and asks for the run explicitly
                    function removeRun(): void {
                        if (_removing || root._clearing) return
                        _removing = true
                        Notifications.removeRunFromHistory(_entry.index, _entry._runLength)
                    }

                    Item {
                        visible: _entry._showSection
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        y: _entry._gapAbove
                        height: _entry._sectionHeight

                        ShellText {
                            id: _secText
                            anchors.left:           parent.left
                            anchors.leftMargin:     4
                            anchors.verticalCenter: parent.verticalCenter
                            text: { root._timeTick; return root.sectionLabel(_entry.modelData.time) }
                            color: Theme.withAlpha(Theme.mix(Theme.subtext, Theme.accent, 0.22), 0.74)
                            font.pixelSize: Settings.fontMicro
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.4
                        }

                        Hairline {
                            anchors.left:           _secText.right
                            anchors.leftMargin:     10
                            anchors.right:          parent.right
                            anchors.verticalCenter: _secText.verticalCenter
                            color:  Theme.withAlpha(Theme.subtext, 0.10)
                        }
                    }

                    // the run's depth, drawn rather than counted: two cards stepping out from
                    // under the header. Declared before it so they paint behind, deepest first.
                    // Loaded only where a stack can stand, so a plain row does not carry two
                    // Shapes it never paints; kept loaded while the run is open so they can fade
                    Loader {
                        anchors.fill: parent
                        active: _entry._showHeader && _entry._stackable
                        sourceComponent: Item {
                            Rectangle {
                                id: _peekBack
                                x: 2 * _entry._peekInset
                                y: _card.y + 2 * _entry._peekStep
                                width: _entry.width - 4 * _entry._peekInset
                                height: _card.height
                                radius: _card.radius
                                antialiasing: true
                                color: Theme.rowFill(false, false)
                                opacity: _entry._peeks >= 2 ? 0.32 : 0
                                visible: opacity > 0.001

                                ColorFade on color { gate: _entry._heightReady }
                                // same hold as the height: a run resized by the model snaps
                                MotionBehavior on opacity {
                                    gate: _entry._heightReady && !root._settling
                                    NumberAnimation { duration: Motion.fast }
                                }

                                OutlineBorder {
                                    radius: _peekBack.radius
                                    outlineWidth: 1
                                    outlineColor: Theme.menuCardBorder
                                    ColorFade on outlineColor { gate: _entry._heightReady }
                                }
                            }

                            Rectangle {
                                id: _peekFront
                                x: _entry._peekInset
                                y: _card.y + _entry._peekStep
                                width: _entry.width - 2 * _entry._peekInset
                                height: _card.height
                                radius: _card.radius
                                antialiasing: true
                                color: Theme.rowFill(false, false)
                                opacity: _entry._peeks >= 1 ? 0.60 : 0
                                visible: opacity > 0.001

                                ColorFade on color { gate: _entry._heightReady }
                                MotionBehavior on opacity {
                                    gate: _entry._heightReady && !root._settling
                                    NumberAnimation { duration: Motion.fast }
                                }

                                OutlineBorder {
                                    radius: _peekFront.radius
                                    outlineWidth: 1
                                    outlineColor: Theme.menuCardBorder
                                    ColorFade on outlineColor { gate: _entry._heightReady }
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: _card
                        x: 0
                        y: _entry._gapAbove + _entry._sectionHeight
                        width: parent.width
                        height: _entry._cardHeight
                        radius: Theme.radiusControl
                        antialiasing: true
                        clip: true
                        color: Theme.rowFill(_entryHover.hovered, _entryTap.pressed)

                        OutlineBorder {
                            radius: _card.radius
                            outlineWidth: 1
                            // a folded stack answers for its run, so a critical entry hiding
                            // underneath still has to reach the outline
                            outlineColor: _entry._critical
                                || (_entry._stacked && _entry._runCritical)
                                ? Theme.withAlpha(Theme.error, 0.50) : Theme.menuCardBorder
                            // same gate as the height above: a recycled row would otherwise
                            // cross-fade the previous notification's urgency colour into view
                            ColorFade on outlineColor { gate: _entry._heightReady }
                        }

                        ColorFade on color { gate: _entry._heightReady }

                        Accessible.role: Accessible.Notification
                        Accessible.name: String(_entry.modelData.appName || "").length > 0
                            ? _entry.modelData.appName + ": " + _summary.text : _summary.text
                        Accessible.description: _body.bodyText
                        Accessible.focusable: true
                        Accessible.onPressAction: _entry._toggleExpand()

                        HoverHandler {
                            id: _entryHover
                            // a disabled ancestor stops presses but not hover on Qt 6, and a
                            // follower still has card height while it collapses into the fold
                            enabled: !_entry._folded
                            cursorShape: (_body.truncated || _body.expanded || _entry._stacked)
                                ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                        TapHandler {
                            id: _entryTap
                            enabled: !root._clearing && !_entry._removing
                            onTapped: eventPoint => {
                                const p = _rightSlot.mapFromItem(_card, eventPoint.position.x, eventPoint.position.y)
                                if (_rightSlot.contains(p)) return
                                _entry._toggleExpand()
                            }
                        }

                        Column {
                            id: _entryContent
                            anchors.left: parent.left
                            anchors.leftMargin: _entry._sidePad
                            anchors.right: parent.right
                            anchors.rightMargin: _entry._sidePad
                            anchors.top: parent.top
                            anchors.topMargin: _entry._topPad
                            spacing: 3

                            Row {
                                id: _metaRow
                                width: parent.width
                                height: visible ? Math.max(16, _appName.implicitHeight) : 0
                                visible: _entry._showHeader
                                spacing: 7

                                readonly property int _nameSpace: Math.max(0, width
                                    - _appIconSlot.width - spacing - _entry._rightGutter)

                                Item {
                                    id: _appIconSlot
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16
                                    height: 16

                                    readonly property string _fallbackSource: String(
                                        _entry.modelData.appName || _entry.modelData.summary || "N").trim()

                                    ShellText {
                                        anchors.centerIn: parent
                                        visible: _recentAppIcon.status !== Image.Ready
                                        text: SafeText.initial(_appIconSlot._fallbackSource, "N")
                                        color: Theme.withAlpha(Theme.subtext, 0.70)
                                        font.pixelSize: Settings.fontMicro
                                        font.weight: Font.DemiBold
                                    }

                                    IconImage {
                                        id: _recentAppIcon
                                        anchors.fill: parent
                                        visible: status === Image.Ready
                                        // without this the themed icon decodes at its native size (often 256px+) to paint 16px
                                        implicitSize: 16
                                        // a deleted temp icon is still a valid path, so only the load failing reveals it
                                        property bool _fellBack: false
                                        readonly property string _primary: _entry._appIconSource
                                        on_PrimaryChanged: _fellBack = false
                                        source: _fellBack ? _entry._appIconFallback : _primary
                                        onStatusChanged: if (status === Image.Error
                                                && _entry._appIconFallback.length > 0
                                                && _entry._appIconFallback !== _primary)
                                            _fellBack = true
                                        asynchronous: true
                                    }
                                }

                                ShellText {
                                    id: _appName
                                    anchors.verticalCenter: parent.verticalCenter
                                    // the chip belongs to the name and follows it; the run
                                    // actions belong to the row and are pushed to its end
                                    width: _stackChip.visible
                                        ? Math.min(_appName.implicitWidth, Math.max(0,
                                            _metaRow._nameSpace - _stackChip.width - _metaRow.spacing))
                                        : _runActions.visible
                                        ? Math.max(0, _metaRow._nameSpace
                                            - _runActions.width - _metaRow.spacing)
                                        : _metaRow._nameSpace
                                    text: _entry.modelData.appName || "Notification"
                                    color: _entry._critical ? Theme.error : Theme.withAlpha(Theme.subtext, 0.70)
                                    font.pixelSize: Settings.fontCaption
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    id: _stackChip
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: _entry._stacked
                                    width: Math.max(16, _stackCount.implicitWidth + 10)
                                    height: 16
                                    radius: 8
                                    antialiasing: true
                                    color: Theme.withAlpha(Theme.accent, 0.14)

                                    ShellText {
                                        id: _stackCount
                                        anchors.centerIn: parent
                                        text: String(_entry._runLength)
                                        color: Theme.withAlpha(Theme.accent, 0.92)
                                        font.pixelSize: Settings.fontMicro
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Row {
                                    id: _runActions
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: parent.height
                                    visible: _entry._stackable && _entry._runOpen
                                    spacing: 6

                                    // the handlers ride a wrapper, as ExpandableBody's pill does: a
                                    // tap on a bare Text inside this card never reported release
                                    Item {
                                        width: _collapseText.implicitWidth
                                        height: parent.height

                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Collapse"
                                        Accessible.focusable: true
                                        Accessible.onPressAction: _historyGrouping.setOpen(_entry._runKey, false)

                                        ShellText {
                                            id: _collapseText
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Collapse"
                                            color: _collapseHover.hovered
                                                ? Theme.accent : Theme.withAlpha(Theme.accent, 0.78)
                                            font.pixelSize: Settings.fontCaption
                                            font.weight: Font.Medium
                                            ColorFade on color { gate: _entry._heightReady }
                                        }

                                        HoverHandler { id: _collapseHover; cursorShape: Qt.PointingHandCursor }
                                        // the exclusive grab keeps the card's tap out of it: that
                                        // handler runs second and would reopen the run it just folded
                                        TapHandler {
                                            enabled: !root._clearing && !_entry._removing
                                            gesturePolicy: TapHandler.ReleaseWithinBounds
                                            onTapped: _historyGrouping.setOpen(_entry._runKey, false)
                                        }
                                    }

                                    ShellText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "·"
                                        color: Theme.withAlpha(Theme.subtext, 0.34)
                                        font.pixelSize: Settings.fontCaption
                                    }

                                    Item {
                                        width: _clearRunText.implicitWidth
                                        height: parent.height

                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Clear all"
                                        Accessible.focusable: true
                                        Accessible.onPressAction: _entry.removeRun()

                                        ShellText {
                                            id: _clearRunText
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Clear all"
                                            color: _clearRunHover.hovered
                                                ? Theme.error : Theme.withAlpha(Theme.subtext, 0.70)
                                            font.pixelSize: Settings.fontCaption
                                            font.weight: Font.Medium
                                            ColorFade on color { gate: _entry._heightReady }
                                        }

                                        HoverHandler { id: _clearRunHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler {
                                            enabled: !root._clearing && !_entry._removing
                                            gesturePolicy: TapHandler.ReleaseWithinBounds
                                            onTapped: _entry.removeRun()
                                        }
                                    }
                                }
                            }

                            ShellText {
                                id: _summary
                                width: Math.max(0, parent.width
                                    - (_metaRow.visible ? 0 : _entry._rightGutter))
                                text: _entry.modelData.summary || "Notification"
                                color: Theme.text
                                font.pixelSize: Settings.fontSize
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            ExpandableBody {
                                id: _body
                                width: parent.width
                                enabled: !root._clearing && !_entry._removing
                                bodyText: _entry.modelData.body || ""
                                bodyColor: Theme.withAlpha(Theme.text, 0.58)
                                collapsedLineCount: 2
                                spacing: 3
                                // a folded card's tap belongs to the run, so More would be a lie
                                showDisclosure: !_entry._stacked
                            }
                        }

                        // one right column for both states: the timestamp rests there and the
                        // remove button takes its place under the pointer, so nothing reflows on hover
                        Item {
                            id: _rightSlot
                            anchors.right: parent.right
                            anchors.rightMargin: _entry._sidePad
                            anchors.top: parent.top
                            anchors.topMargin: _entry._topPad
                                + Math.round((_entry._firstLineHeight - height) / 2)
                            width: Math.max(24, _entryTime.implicitWidth, _removeButton.width)
                            height: 24
                            z: 2

                            ShellText {
                                id: _entryTime
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: { root._timeTick; return root.formatTime(_entry.modelData.time) }
                                color: Theme.withAlpha(Theme.subtext, 0.42)
                                font.pixelSize: Settings.fontMicro
                                opacity: _entryHover.hovered ? 0 : 1
                                MotionBehavior on opacity { gate: _entry._heightReady; NumberAnimation { duration: Motion.fast } }
                            }

                            Rectangle {
                                id: _removeButton
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                // a folded card clears a whole run, so the control says how many
                                width: _entry._stacked
                                    ? Metrics.snap4Up(_removeGlyph.implicitWidth + _removeRow.spacing
                                        + _removeLabel.implicitWidth + 18)
                                    : 24
                                height: 24
                                radius: 12
                                antialiasing: true

                                color: _removeTap.pressed
                                    ? Theme.withAlpha(Theme.error, 0.24)
                                    : _removeHover.hovered ? Theme.withAlpha(Theme.error, 0.17) : Theme.withAlpha(Theme.subtext, 0.08)
                                opacity: _entryHover.hovered ? 1.0 : 0.0
                                visible: opacity > 0.001
                                scale: _removeTap.pressed ? 0.94 : 1.0

                                ColorFade on color { gate: _entry._heightReady }
                                MotionBehavior on opacity { gate: _entry._heightReady; NumberAnimation { duration: Motion.fast } }

                                OutlineBorder {
                                    radius: _removeButton.radius
                                    outlineWidth: 1
                                    outlineColor: _removeHover.hovered ? Theme.withAlpha(Theme.error, 0.36) : Theme.menuControlLine
                                    ColorFade on outlineColor { gate: _entry._heightReady }
                                }
                                MotionBehavior on scale { gate: _entry._heightReady; NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
                                Accessible.role: Accessible.Button
                                Accessible.name: "Remove notification"
                                Accessible.focusable: true
                                Accessible.onPressAction: _entry.removeSelf()

                                HoverHandler { id: _removeHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { id: _removeTap; enabled: !root._clearing && !_entry._removing; onTapped: _entry.removeSelf() }

                                Row {
                                    id: _removeRow
                                    anchors.centerIn: parent
                                    // the glyph's ink sits a pixel up and left of its box centre
                                    // (measured at 11px; the font reports the whole cell as ink, so
                                    // TextMetrics cannot say so), and the box is nudged to match
                                    anchors.horizontalCenterOffset: 1
                                    spacing: 5

                                    ShellText {
                                        id: _removeGlyph
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: 1
                                        text: "󰅖"
                                        color: _removeHover.hovered ? Theme.error : Theme.withAlpha(Theme.subtext, 0.56)
                                        font.pixelSize: Settings.fontCaption
                                    }

                                    ShellText {
                                        id: _removeLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: _entry._stacked
                                        text: "Clear " + _entry._runLength
                                        color: _removeHover.hovered ? Theme.error : Theme.withAlpha(Theme.subtext, 0.72)
                                        font.pixelSize: Settings.fontCaption
                                    }
                                }
                            }
                        }
                    }
            }
        }

        ListEdgeLines {
            anchors.fill: _historyList
            visible: Notifications.hasHistory
            opacity: _historyList.opacity
            z: 2
            list: _historyList
            maxOpacity: 0.72
        }

        MenuScrollThumb {
            list: _historyList
            fadeMultiplier: _historyList.opacity
            trackInset: 4
            rightInset: 2
            shown: Notifications.hasHistory
            z: 3
        }
    }
}
