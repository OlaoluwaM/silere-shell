pragma Singleton

import QtQuick

QtObject {
    property bool activeFullscreen: false
    property int refreshCount: 0

    function refreshToplevels(): void { refreshCount++ }
}
