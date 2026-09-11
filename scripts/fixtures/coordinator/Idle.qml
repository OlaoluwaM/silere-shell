pragma Singleton

import QtQuick

QtObject {
    id: root

    property bool isIdle: false
    readonly property bool isQuiet: isIdle
}
