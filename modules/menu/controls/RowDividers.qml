pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"

Repeater {
    id: root

    required property Item column
    property color lineColor: Theme.menuDivider
    readonly property real _dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1

    function present(item): bool {
        if (!item) return false
        if (item.layoutPresent !== undefined)
            return item.layoutPresent === true
        // standard card rows expose their edge or divider contract. Their animated height is presentation only and must not drive the scan
        if (item.topRadius !== undefined
                || item.suppressDividerAbove !== undefined)
            return item.visible
        return item.visible && item.height > 0.5
    }

    // a row whose fill is showing; one that doesn't expose the contract, or can't be interacted with, never counts
    function engaged(item): bool {
        if (!item) return false
        return (item.rowInteractive ?? true) === true
            && ((item.rowHovered ?? false) === true || (item.rowPressed ?? false) === true)
    }

    // a radius group (CollapsibleSection) has no hover of its own: the line beside it answers to the
    // group's edge row, first when the group sits below the line and last when it sits above.
    // Same walk and presence rule as SettingsCard._edgeEl
    function edgeRow(item, first): var {
        if (!item || item.isRadiusGroup !== true || !item.radiusColumn) return item
        const ch = item.radiusColumn.children
        for (let n = 0; n < ch.length; n++) {
            const c = ch[first ? n : ch.length - 1 - n]
            if (!root.present(c)) continue
            const inner = root.edgeRow(c, first)
            if (inner) return inner
        }
        return null
    }

    // index of the row above each line, -1 for none; the scan that finds it also decides whether a line exists
    readonly property var _aboveIndex: {
        const result = []
        const children = column ? column.children : []
        let above = -1
        for (let i = 0; i < children.length; i++) {
            result.push(above)
            const c = children[i]
            if (root.present(c) && !(c.suppressDividerAbove ?? false)) above = i
        }
        return result
    }
    readonly property var _sepVisible: _aboveIndex.map(i => i >= 0)

    model: column ? column.children.length : 0
    delegate: Rectangle {
        id: _line
        required property int index
        readonly property Item row: root.column ? (root.column.children[index] ?? null) : null
        readonly property bool hasRowAbove: root._sepVisible[index] ?? false
        readonly property Item rowAbove: root.column
            ? (root.column.children[root._aboveIndex[index]] ?? null) : null
        // a hovered row's fill runs to the card edge past the inset line and covers only the line at
        // its own top, so both lines beside it fade and the fill reads as one clean band
        readonly property bool _engaged: root.engaged(root.edgeRow(row, true))
            || root.engaged(root.edgeRow(rowAbove, false))
        // a separate factor: the row-driven opacity below must follow a collapsing row frame for frame
        property real _fade: _engaged ? 0 : 1
        MotionBehavior on _fade {
            id: _fadeMotion
            NumberAnimation {
                duration: _fadeMotion.targetValue < 0.5 ? Motion.hoverIn : Motion.hoverOut
                easing.type: Easing.OutCubic
            }
        }

        visible: row !== null && (row.layoutPresent ?? row.visible) && hasRowAbove
              && !(row.suppressDividerAbove ?? false) && opacity > 0.01
        x: (root.column ? root.column.x : 0) + 14
        // snap the leftover local offset so every divider lands on the same physical pixel at fractional scales
        y: Math.round(((root.column ? root.column.y : 0)
            + (row ? row.y : 0)) * root._dpr) / root._dpr
        width: root.column
            ? Math.max(0, root.column.width - 28)
            : 0
        height: Math.max(1, Math.ceil(root._dpr - 0.5)) / root._dpr
        opacity: row
            ? Math.min(1, Math.max(0, (row.height - 4) / 20)) * Math.min(1, row.opacity * 2) * _fade
            : 0
        antialiasing: false
        color: root.lineColor
    }
}
