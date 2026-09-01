import QtQuick
import Quickshell.Services.SystemTray
import "../../../config"
import "../../../services"

// StatusActionPill, not the inline SNI row TrayWidget.qml draws (this site keeps
// ShellSettings.trayWidget false) -- a click here opens TrayPopupWindow, a
// minimalist text-driven list of the same SystemTray items, instead of icons
// inline on the bar. The pill carries no icon roster itself, just a quiet glyph,
// so all it needs to know is whether the tray has anything to show.
StatusActionPill {
    id: root

    property var screen: null
    property real menuAnchorX: 0

    // items is an UntypedObjectModel: it has no count property of its own (that's
    // only ever synthesized for a Repeater/ListView bound to it), so read length off
    // values, the one property it does publish with a change signal
    show: SystemTray.items.values.length > 0
    hintScreen: root.screen
    hintText: root.show ? "Click tray menu" : ""

    glyph: "󰀻"
    // single-state widget, so the reference is the glyph itself
    glyphAlignReference: "󰀻"

    function _syncMenuAnchor(): void {
        const pt = root.mapToItem(null, root.width / 2, 0)
        if (isFinite(pt.x)) root.menuAnchorX = pt.x
    }

    onXChanged: root._syncMenuAnchor()
    onYChanged: root._syncMenuAnchor()
    onWidthChanged: root._syncMenuAnchor()
    Component.onCompleted: root._syncMenuAnchor()

    onActivated: {
        root._syncMenuAnchor()
        TrayPopupState.toggleAt(root.menuAnchorX, root.screen, root)
    }
}
