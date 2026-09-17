pragma Singleton

import QtQuick
import Quickshell.Services.SystemTray

// State for TrayPopupWindow (modules/traypopup), the minimalist tray list this fork
// shows from the bar instead of upstream's inline SNI icon row (TrayWidget.qml,
// gated behind ShellSettings.trayWidget which stays false at this site).
AnchoredPopupState {
    id: root

    anchorRecoveryMs: 0
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
        openAt(x, screen, source)
    }
}
