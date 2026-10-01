pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "services"

ShellRoot {
    id: root

    Component.onCompleted: { void ShellSettings.ready }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }

    property int _scaleChanges: 0
    property int _readyChanges: 0

    // a reload that assigns only what the file changed leaves untouched keys and readiness alone
    Connections {
        target: ShellSettings
        function onUiScaleChanged() { root._scaleChanges++ }
        function onReadyChanged() { root._readyChanges++ }
    }

    IpcHandler {
        target: "migrationProbe"

        function resetCounters(): void { root._scaleChanges = 0; root._readyChanges = 0 }
        function counters(): string {
            return JSON.stringify({ uiScale: root._scaleChanges, ready: root._readyChanges })
        }

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
        function retiredSettingsAbsent(): bool {
            const keys = ["mediaProgress", "mediaVisualizerPreset",
                "mediaVisualizerStyle", "mediaVisualizerPosition"]
            return keys.every(key => ShellSettings.schemaFor(key) === null
                && ShellSettings[key] === undefined)
        }
    }
}
