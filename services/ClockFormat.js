.pragma library

// The bar's clock words without the bar's clock: pure functions of a Date and the 12-hour
// setting, so the lock process can show the same time without starting DateTime, whose
// catch-up watchers would pull Network and TimeZoneWatch into a process that only formats.

// qt only counts 12-hour when AP shares the format string; "h" alone still reads 0-23
function clockHour(d, twelveHour) {
    if (!twelveHour) return Qt.formatDateTime(d, "HH")
    const text = Qt.formatDateTime(d, "h'|'AP")
    const at = text.indexOf("|")
    return at < 0 ? text : text.slice(0, at)
}

function clockSuffix(d, twelveHour) {
    return twelveHour ? Qt.formatDateTime(d, "AP") : ""
}

function clockText(d, twelveHour) {
    const suffix = clockSuffix(d, twelveHour)
    return clockHour(d, twelveHour) + ":" + Qt.formatDateTime(d, "mm")
        + (suffix.length > 0 ? " " + suffix : "")
}
