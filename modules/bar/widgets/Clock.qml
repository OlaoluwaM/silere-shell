import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

Item {
    id: root

    property var screen: null
    property bool compact: ShellSettings.barCompact
    property bool barActive: true
    readonly property bool _animatable: root.barActive && !Idle.isIdle
    property real menuAnchorX: 0
    readonly property int _horizontalPadding: Metrics.pillPadFor(compact)

    // a keybind opens with no trigger widget, so the state's fallback x has to stay fresh
    readonly property bool _anchorFallbackBar: !!root.screen && root.screen.name === Monitors.overlayBarName

    // The calendar hangs from the clock as it rests. A date shown only while the pointer is on
    // the clock widens it away from the time, which keeps its place in a side zone, so there
    // the time is what stays put. A centred clock widens about its own middle, and a date that
    // is always shown is part of the clock at rest
    readonly property Item _anchorItem: ShellSettings.clockShowDate
        || ShellSettings.barWidgetOrderCenterKeys.indexOf("clock") !== -1 ? root : _time
    on_AnchorItemChanged: _anchorSettle.restart()

    function _syncMenuAnchor(): void {
        const item = root._anchorItem
        const pt = item.mapToItem(null, item.width / 2, 0)
        if (!isFinite(pt.x)) return
        root.menuAnchorX = pt.x
        CalendarState.publishFallbackAnchor(root.screen, pt.x)
    }
    on_AnchorFallbackBarChanged: root._syncMenuAnchor()
    Connections {
        target: CalendarState
        // mapToItem sees no ancestor geometry, so the cached x is a stale layout pass by now
        function onOpenChanged() {
            if (CalendarState.open && CalendarState.anchorSource === null) root._syncMenuAnchor()
        }
    }

    // A resize reaches these handlers partway through a layout pass, before the zone has moved
    // the clock to make room, and mapToItem reads those stale positions: each frame of the date
    // easing open measured the time a frame's growth away from where it stood. A turn later
    // the pass is done, and the time has not moved
    Timer {
        id: _anchorSettle
        interval: 0
        onTriggered: root._syncMenuAnchor()
    }
    onXChanged: _anchorSettle.restart()
    onYChanged: _anchorSettle.restart()
    onWidthChanged: {
        _anchorSettle.restart()
        // seconds and the date are toggled from here, so the clock resizes under the pointer
        if (_hover.hovered) root._syncHint()
    }
    Component.onCompleted: root._syncMenuAnchor()
    onBarActiveChanged: root._syncHint()

    readonly property bool mirrored: ShellSettings.barWidgetOrderLeftKeys.indexOf("clock") !== -1

    readonly property bool show: ShellSettings.barShowClock
    property real _showProgress: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _showProgress > 0.001
    implicitWidth: (_content.implicitWidth + root._horizontalPadding * 2) * _showProgress
    implicitHeight: _content.implicitHeight
    visible: layoutVisible
    enabled: show
    opacity: _showProgress
    clip: _showProgress < 0.999

    MotionBehavior on _showProgress {
        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
    }

    // the same gate as a Pill's, so an idle bar drops the clock's hover with the other widgets'
    readonly property bool _hoverEnabled: root.enabled && root.visible && root.barActive
        && !Idle.isIdle
    readonly property bool _hov: _hoverEnabled && _hover.hovered && ShellSettings.barHoverHighlight
    readonly property color _cSub:   _hov ? Theme.mix(Theme.subtext, Theme.accent, 0.30) : Theme.subtext
    readonly property color _cText:  _hov ? Theme.mix(Theme.text,    Theme.accent, 0.30) : Theme.text
    readonly property color _cFaint: _hov ? Theme.mix(Theme.withAlpha(Theme.text, 0.65), Theme.accent, 0.30)
                                          : Theme.withAlpha(Theme.text, 0.65)
    readonly property color _cSec:   _hov ? Theme.mix(Theme.accent, Theme.text, 0.22)
                                          : Theme.withAlpha(Theme.accent, 0.82)

    function _syncHint(): void {
        if (!root.barActive || !_hover.hovered) {
            BarHintState.release(root)
            return
        }
        const point = root.mapToItem(null, root.width / 2, 0)
        BarHintState.request(root, root.screen, point.x,
            "Click calendar · middle-click date and seconds")
    }

    HoverHandler {
        id: _hover
        enabled: root._hoverEnabled
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            root._syncHint()
            root._peekOnHover(hovered)
        }
    }

    // the pointer's side of the date peek. An argument, not the handler's state, so it is testable
    function _peekOnHover(hovered: bool): void {
        if (hovered) {
            BarHover.widget = root
            _datePeekRelease.stop()
            if (!root._datePeek) _datePeekDelay.restart()
        } else {
            _datePeekDelay.stop()
            if (root._datePeek && !root._calendarHeld) root._foldDate()
        }
    }

    // at once when the pointer is already on another widget, after the wait when it only slipped off
    function _foldDate(): void {
        if (BarHover.elsewhere(root)) root._datePeek = false
        else _datePeekRelease.restart()
    }

    // the date reads on hover when it is not already shown; only meaningful with clockShowDate off
    property bool _datePeek: false
    readonly property bool _dateRevealed: root._datePeek && root._hoverEnabled
        && ShellSettings.valuesOnHover

    // The calendar's surface covers the screen to catch the closing tap, so opening it from the
    // clock takes the pointer away although it has not moved. A date that was out stays out
    // until that calendar closes; one the click beat stays in, so the bar holds still either way
    readonly property bool _calendarHeld: CalendarState.open && CalendarState.anchorSource === root
    on_CalendarHeldChanged: {
        if (root._calendarHeld) {
            _datePeekDelay.stop()
            _datePeekRelease.stop()
        } else if (root._datePeek && !_hover.hovered) {
            root._foldDate()
        }
    }

    Timer {
        id: _datePeekDelay
        interval: 80
        onTriggered: root._datePeek = true
    }
    // The clock ends a few pixels past its last digit, so a pointer thrown at it overshoots
    // and comes back, and a closing calendar hands the pointer back a moment after it closes.
    // Closing at once on either would fold the date away only to open it again
    Timer {
        id: _datePeekRelease
        interval: Motion.hoverLinger
        onTriggered: root._datePeek = false
    }
    // read by the logic probe alone: whether the date is on its way in
    readonly property bool _dateFolding: _datePeekRelease.running
    // the wait is for a slip; a pointer now on another widget is not coming straight back
    Connections {
        target: BarHover
        function onWidgetChanged() {
            if (!BarHover.elsewhere(root) || !_datePeekRelease.running) return
            _datePeekRelease.stop()
            root._datePeek = false
        }
    }
    Component.onDestruction: BarHintState.release(root)

    function _openCalendar(): void {
        root._syncMenuAnchor()
        CalendarState.toggleAt(root.menuAnchorX, root.screen, root)
    }

    Row {
        id: _content
        x: root._horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        layoutDirection: root.mirrored ? Qt.RightToLeft : Qt.LeftToRight

        Item {
            id: _dateSectionClip
            anchors.verticalCenter: parent.verticalCenter
            height:  _dateRow.implicitHeight
            // the day and date ease their own widths; easing their sum again stalls until they settle
            property real _shown: ShellSettings.clockShowDate || root._dateRevealed ? 1 : 0
            MotionBehavior on _shown {NumberAnimation { duration: Motion.width; easing.type: Easing.OutCubic } }
            width:   (_dateRow.implicitWidth + Metrics.clockDateGapFor(root.compact)) * _shown
            opacity: _shown
            visible: _shown > 0.001
            // only while the date eases in or out, or its own width eases after a font change and
            // the text overruns it; a standing clip node breaks batching
            clip:    _shown < 1 || _dateCore.width < _dateCore.implicitWidth

            Row {
                id: _dateRow
                anchors.verticalCenter: parent.verticalCenter
                x: root.mirrored ? parent.width - width : 0
                spacing: 0

                CollapsingText {
                    text:     DateTime.cachedDayName
                    color:    root._cSub
                    animate:  root._animatable
                    expanded: !ShellSettings.compactDate && !root.compact
                }
                RollingText {
                    id: _dateCore
                    text:    DateTime.cachedDateCore
                    color:   root._cSub
                    animate: root._animatable
                }
            }
        }

        Row {
            id: _time
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            RollingText {
                tabularDigits: true
                reserveText: "00"
                horizontalAlignment: Text.AlignRight
                text:    DateTime.cachedHour
                color:   root._cText
                animate: root._animatable
            }
            RollingText { text: ":"; color: root._cText; animate: root._animatable }
            RollingText {
                tabularDigits: true
                reserveText: "00"
                horizontalAlignment: Text.AlignRight
                text:    DateTime.cachedMinute
                color:   root._cText
                animate: root._animatable
            }
            CollapsingText {
                text:     DateTime.cachedSeconds
                color:    root._cSec
                animate:  root._animatable
                expanded: ShellSettings.showSeconds
                reserveText: ":00"
                tabularDigits: true
            }
            CollapsingText {
                text:     DateTime.cachedAmPm ? " " + DateTime.cachedAmPm : ""
                color:    root._cFaint
                animate:  root._animatable
                expanded: ShellSettings.clock12h
            }
        }
    }

    readonly property string accessibleName: "Clock, " + DateTime.cachedHour + ":" + DateTime.cachedMinute
        + (DateTime.cachedAmPm.length > 0 ? " " + DateTime.cachedAmPm : "")
        + ", " + DateTime.cachedWeekday + " " + DateTime.cachedMonthDay
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.focusable: root.show
    Accessible.onPressAction: root._openCalendar()

    TapHandler {
        id: _calTap
        enabled: root.show && root.barActive
        gesturePolicy: TapHandler.ReleaseWithinBounds
        acceptedButtons: Qt.LeftButton
        onTapped: root._openCalendar()
    }

    TapHandler {
        id: _cycleTap
        enabled: root.show && root.barActive
        gesturePolicy: TapHandler.ReleaseWithinBounds
        acceptedButtons: Qt.MiddleButton
        onTapped: {
            // a peeked date would hide the step that turns the date off
            _datePeekRelease.stop()
            root._datePeek = false
            ShellSettings.batch(() => {
                const s = ShellSettings.showSeconds
                const d = ShellSettings.clockShowDate
                if (!s && !d)     { ShellSettings.showSeconds = true }
                else if (s && !d) { ShellSettings.showSeconds = false; ShellSettings.clockShowDate = true }
                else if (!s && d) { ShellSettings.showSeconds = true }
                else              { ShellSettings.showSeconds = false; ShellSettings.clockShowDate = false }
            })
        }
    }
}
