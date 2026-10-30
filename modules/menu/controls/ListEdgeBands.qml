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

    // Read through the rows' own index, not itemAtIndex(): that call is no dependency, and
    // a row sorted onto the edge, as a network just connected is, left the answer stale.
    // Every index read up to the match is one, so whichever row's renumbering lands last
    // reruns this against the settled order
    function _engaged(index: int, top: bool): bool {
        if (index < 0) return false
        const rows = root.list.contentItem.children
        for (let i = 0; i < rows.length; i++) {
            const row = rows[i]
            if (row.index === index)
                return (top ? row.rowTopEngaged : row.rowBottomEngaged) === true
        }
        return false
    }
}
