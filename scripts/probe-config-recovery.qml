pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "config"
import "services"

ShellRoot {
    id: root

    readonly property string firstPayload: "{\"payload\":\"first\"}"
    readonly property string secondPayload: "{\"payload\":\"second\"}"

    property string payload: firstPayload
    property int phase: 0
    property int checks: 0
    property int failures: 0
    property bool blockedReported: false
    property bool secondFailureSeen: false
    property bool readyDroppedAfterFailure: false

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL", label)
    }

    Timer {
        interval: 20
        running: !root.blockedReported
        repeat: true
        onTriggered: {
            if (ConfigStore.ready || ConfigStore.error.length === 0 || !store.pending) return
            root.blockedReported = true
            root.check(ConfigStore.error.indexOf("Could not create") >= 0,
                "the blocked configuration path reports its directory error")
            root.check(store.pending,
                "the queued write remains pending while its directory is blocked")
            console.warn("PROBE-CONFIG-BLOCKED")
        }
    }

    PersistedFile {
        id: store
        path: ConfigStore.settingsPath
        serialize: () => root.payload

        onSaved: {
            if (root.phase !== 0) return
            root.check(root.blockedReported,
                "the first write waits for the blocked-directory observation")
            root.phase = 1
            console.warn("PROBE-CONFIG-FIRST-SAVED")
        }
    }

    Loader {
        id: secondWriter
        active: false
        sourceComponent: PersistedFile {
            id: secondStore
            path: ConfigStore.settingsPath
            serialize: () => root.secondPayload

            Component.onCompleted: secondStore.queue()

            onSaveFailed: {
                root.secondFailureSeen = true
                root.readyDroppedAfterFailure = !ConfigStore.ready
                console.warn("PROBE-CONFIG-SECOND-WRITE-FAILED")
            }

            onSaved: {
                root.check(root.secondFailureSeen,
                    "the replacement write fails once after its directory disappears")
                root.check(root.readyDroppedAfterFailure,
                    "the failed write stops advertising directory readiness")
                root.check(ConfigStore.ready && !secondStore.pending,
                    "the replacement write finishes only after directory recovery")
                if (root.failures === 0)
                    console.warn("PROBE-CONFIG-RECOVERY passed " + root.checks + " checks")
                console.warn("PROBE-CONFIG-SECOND-SAVED")
                console.warn("PROBE-CONFIG-RECOVERY-DONE")
            }
        }
    }

    IpcHandler {
        target: "configRecovery"

        function writeSecond(): string {
            if (root.phase !== 1) return "not ready"
            root.phase = 2
            secondWriter.active = true
            return "queued"
        }
    }

    Component.onCompleted: store.queue()
}
