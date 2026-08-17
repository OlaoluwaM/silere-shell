pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

// State for TrayPopupWindow (modules/traypopup), the minimalist tray list this fork
// shows from the bar instead of upstream's inline SNI icon row (TrayWidget.qml,
// gated behind ShellSettings.trayWidget which stays false at this site). Mirrors
// CalendarState's open/anchor shape -- no persistence here, the tray has none to keep.
Singleton {
    id: root

    property bool open: false
    property real anchorX: 0
    property QtObject anchorSource: null
    property ShellScreen triggerScreen: null
    readonly property real effectiveAnchorX: {
        const live = Number(root.anchorSource?.menuAnchorX)
        return isFinite(live) ? live : root.anchorX
    }
    // follows the pill down if its BarZone slot is ever actually torn down (widget
    // disabled in settings, bar recreated on a screen/position change)
    onAnchorSourceChanged: if (open && anchorSource === null) close()
    // the pill's own slot stays loaded across an empty tray (its BarZone visibility
    // gate has no setting to disable, so `wanted` never flips) -- it only fades out,
    // so anchorSource never nulls on its own. Watch the tray directly instead.
    Connections {
        target: SystemTray.items
        // items is an UntypedObjectModel: no count property of its own, only values
        // (QObjectList) with its own change signal -- same reasoning as the pill's show gate
        function onValuesChanged() { if (root.open && SystemTray.items.values.length === 0) root.close() }
    }

    function toggleAt(x: real, screen, source): void {
        if (open) { close(); return }
        anchorX = x
        anchorSource = source ?? null
        triggerScreen = screen ?? null
        open = true
    }
    function close(): void {
        if (open) open = false
        anchorSource = null
        triggerScreen = null
    }
}
