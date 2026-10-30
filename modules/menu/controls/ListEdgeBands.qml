import QtQuick

// RowDividers' edge contract for a list that fills a card row: the card's line above the
// list answers to the list's first row, and the line below to its last. A row counts only
// while it rests against the line: scrolled, the list's edge holds other rows, half hidden.
// Delegates report their bands as rowTopEngaged and rowBottomEngaged, as a card row would
QtObject {
    id: root

    required property ListView list

    readonly property bool topEngaged: root.list.visible && root.list.atYBeginning
        && root._engaged(0, true)
    readonly property bool bottomEngaged: root.list.visible && root.list.atYEnd
        && root._engaged(root.list.count - 1, false)

    function _engaged(index: int, top: bool): bool {
        // the list builds its rows after count changes; contentHeight follows the build
        if (index < 0 || root.list.contentHeight <= 0) return false
        const item = root.list.itemAtIndex(index)
        // reading index rebinds when that row moves off the edge without the count changing
        if (!item || item.index !== index) return false
        return (top ? item.rowTopEngaged : item.rowBottomEngaged) === true
    }
}
