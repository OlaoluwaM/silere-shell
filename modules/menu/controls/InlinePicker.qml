import QtQuick

Column {
    id: root

    property bool open: false
    property Component content: null
    // RowDividers' edge contract, passed through from content that exposes it: the card's
    // lines above and below the picker sit on the content's own first and last rows
    readonly property bool rowTopEngaged: _loader.item?.rowTopEngaged === true
    readonly property bool rowBottomEngaged: _loader.item?.rowBottomEngaged === true

    width: parent ? parent.width : 0
    spacing: 0

    CollapsibleSection {
        id: _section
        width: root.width
        expanded: root.open
        list: true

        Loader {
            id: _loader
            width: parent.width
            // the section animates to 0, not this Loader's parent - the content column never shrinks
            active: root.open || _section.height > 0.5
            height: item ? item.implicitHeight : 0
            sourceComponent: root.content
        }
    }
}
