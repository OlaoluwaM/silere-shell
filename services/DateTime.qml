pragma Singleton

import QtQuick
import Quickshell
import "ClockFormat.js" as ClockFormat

Singleton {
    id: root

    function clockNeeded(barClock: bool, overview: bool, homeActive: bool,
            calendarOpen: bool): bool {
        return (barClock && !overview) || homeActive || calendarOpen
    }

    readonly property bool _clockNeeded: root.clockNeeded(
        ShellSettings.barShowClock, OverviewState.active,
        MenuState.homeActive, CalendarState.open)

    // a monotonic timer stops across suspend, so the next tick can land up to a minute after wake
    property bool _resync: false

    SystemClock {
        id: clock
        enabled: root._clockNeeded && !root._resync
        precision: ShellSettings.barShowClock && ShellSettings.showSeconds
            && !Idle.isIdle && !OverviewState.active
            ? SystemClock.Seconds : SystemClock.Minutes
    }

    property string _lastDay:       ""
    property string _lastMinute:    ""
    property string cachedDayName:  ""
    property string cachedDateCore: ""
    property string cachedLongDate: ""
    property string cachedWeekday:  ""
    property string cachedMonthDay: ""
    property string cachedWeek:     ""
    property string cachedHour:     ""
    property string cachedMinute:   ""
    property string cachedAmPm:     ""
    property string cachedSeconds:  ""

    Component.onCompleted: _update(new Date())

    // the words live in ClockFormat so the lock process can share them without this service
    function clockHour(d): string { return ClockFormat.clockHour(d, ShellSettings.clock12h) }

    function clockSuffix(d): string { return ClockFormat.clockSuffix(d, ShellSettings.clock12h) }

    function clockText(d): string { return ClockFormat.clockText(d, ShellSettings.clock12h) }

    function isoWeek(d): int {
        const t = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        t.setDate(t.getDate() + 3 - (t.getDay() + 6) % 7)
        const w1 = new Date(t.getFullYear(), 0, 4)
        return 1 + Math.round(((t - w1) / 86400000 - 3 + (w1.getDay() + 6) % 7) / 7)
    }

    Connections {
        target: clock
        function onDateChanged() { root._update() }
        // enabledChanged fires before the clock re-reads the time, so clock.date is still the old one
        function onEnabledChanged() { if (clock.enabled) root._update(new Date()) }
    }

    Connections {
        target: ShellSettings
        function onClock12hChanged() { root._refreshMinute() }
        function onShowSecondsChanged() { root._update(new Date()) }
        function onBarShowClockChanged() { root._refreshMinute() }
    }

    Connections {
        target: Idle
        function onIsIdleChanged() {
            root.catchUp()
            root._update(new Date())
        }
    }

    // NetworkManager parks every device for sleep and brings them back within seconds of wake
    Connections {
        target: Network
        function onConnectedChanged() { root.catchUp() }
    }

    Connections {
        target: CalendarState
        function onOpenChanged() { if (CalendarState.open) root.catchUp() }
    }

    Connections {
        target: MenuState
        function onOpenChanged() { if (MenuState.open) root.catchUp() }
    }

    // cycling the clock off and on re-arms its stalled timer; the fresh Date covers the
    // moment between, since clock.date is only as new as the last tick
    function catchUp(): void {
        const now = new Date()
        if (!clock.enabled
                || Qt.formatDateTime(now, "yyyyMMddHHmm") === root._lastMinute) return
        root._resync = true
        root._resync = false
        root._update(now)
    }

    Connections {
        target: OverviewState
        function onActiveChanged() { if (!OverviewState.active) root._update(new Date()) }
    }

    // clock.date is frozen at its last tick's old-zone wall time for up to 60s; derive
    // from a fresh Date now instead, and let the next tick carry on correctly on its own
    Connections {
        target: TimeZoneWatch
        function onSwitched() {
            root._lastDay = ""
            root._lastMinute = ""
            root._update(new Date())
        }
    }

    function _refreshMinute(): void {
        root._lastMinute = ""
        root._update(new Date())
    }

    // no explicit arg means "now, as SystemClock last saw it"; only its own dateChanged may
    // rely on that. Every other trigger passes a fresh Date(), since clock.date can be a whole
    // tick behind (see the TimeZoneWatch handler above)
    function _update(at): void {
        const current = at ?? clock.date
        const minute = Qt.formatDateTime(current, "yyyyMMddHHmm")
        if (minute !== _lastMinute) {
            _lastMinute = minute
            const day = minute.slice(0, 8)
            if (day !== _lastDay) {
                _lastDay        = day
                cachedDayName   = Qt.formatDateTime(current, "ddd ")
                cachedDateCore  = Qt.formatDateTime(current, "MMM dd")
                cachedLongDate  = Qt.formatDateTime(current, "dddd, MMMM d")
                cachedWeekday   = Qt.formatDateTime(current, "dddd")
                cachedMonthDay  = Qt.formatDateTime(current, "MMMM d")
                cachedWeek      = String(isoWeek(current))
            }
            cachedMinute = Qt.formatDateTime(current, "mm")
            cachedHour = root.clockHour(current)
            cachedAmPm = root.clockSuffix(current)
        }
        if (!ShellSettings.barShowClock || !ShellSettings.showSeconds) {
            cachedSeconds = ""
        } else if (!Idle.isIdle || cachedSeconds.length === 0) {
            cachedSeconds = ":" + String(current.getSeconds()).padStart(2, "0")
        }
    }
}
