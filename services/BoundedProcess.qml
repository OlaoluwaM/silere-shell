import QtQuick
import Quickshell
import Quickshell.Io

Process {
    id: root

    property int timeoutMs: 0
    property bool timedOut: false

    signal timeoutReached()

    property Connections _runningWatch: Connections {
        target: root
        function onRunningChanged() {
            if (root.running) root.timedOut = false
        }
    }

    property Timer _timeout: Timer {
        interval: Math.max(1, root.timeoutMs)
        running: root.running && root.timeoutMs > 0
        onTriggered: {
            if (!root.running) return
            root.timedOut = true
            root.running = false
            root.timeoutReached()
        }
    }

    // running = false is only a SIGTERM and Process exposes no signal(): a child that traps it
    // stays running forever, so timeoutMs is not a bound until the pid is killed outright
    property Timer _killGrace: Timer {
        interval: 2000
        running: root.timedOut && root.running
        onTriggered: {
            const pid = root.processId
            if (root.running && pid > 0)
                Quickshell.execDetached(["kill", "-KILL", String(pid)])
        }
    }
}
