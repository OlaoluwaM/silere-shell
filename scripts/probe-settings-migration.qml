pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "services"

ShellRoot {
    Component.onCompleted: { void ShellSettings.ready }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }

    IpcHandler {
        target: "migrationProbe"

        function status(): string {
            return JSON.stringify({ ready: ShellSettings.ready,
                error: ShellSettings.settingsError, height: ShellSettings.barHeight })
        }
        function edit(): void {
            ShellSettings.barShowClock = !ShellSettings.barShowClock
            ShellSettings.uiScale = 1.1
            ShellSettings.batch(() => ShellSettings.barHeight = 48)
        }
        function retry(): void { ShellSettings._applyText(ShellSettings._diskText) }
    }
}
