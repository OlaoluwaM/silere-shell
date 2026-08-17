pragma Singleton

// Read-only system info for the System page's fetch card. Everything but
// uptime is static for the life of the session, so each is read once and cached;
// uptime is the only field that ticks, and only while the page that shows it
// is open. The System page is this singleton's only consumer, so unlike
// SysInfo.qml (which keeps /proc polling in the background for the always-visible
// vitals chips), nothing here runs until the page itself is.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // pushed by the System page while it is loaded; the same push-in split
    // WifiProfile uses for its details panel, since nothing else in the
    // shell ever needs this data
    property bool active: false
    function setActive(next: bool): void { root.active = next }

    property string osName: ""
    property string kernel: ""
    property string hostname: ""
    property string compositorVersion: ""
    readonly property string compositorLabel: root.compositorVersion.length > 0
        ? "Hyprland " + root.compositorVersion : "Hyprland"
    readonly property string shellLabel: "silere-shell"

    property real _uptimeSecs: 0
    // matches SysInfo.uptimeLabel's shape ("2h 14m" / "3d 4h") for consistency
    // with the vitals chips, even though the two never share a poll
    readonly property string uptimeLabel: {
        if (root._uptimeSecs <= 0) return "—"
        const s = Math.floor(root._uptimeSecs)
        const d = Math.floor(s / 86400)
        const h = Math.floor((s % 86400) / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    // PRETTY_NAME is usually quoted ("NixOS 26.05 (Yarara)"); unquoted is valid
    // os-release too, so the strip is best-effort rather than assumed
    function _applyOsRelease(text: string): void {
        const m = /^PRETTY_NAME=(.*)$/m.exec(text)
        if (!m) return
        root.osName = SafeText.singleLineText(m[1].replace(/^"|"$/g, ""), 128)
    }

    FileView {
        id: _osRelease
        path: "/etc/os-release"
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root._applyOsRelease(_osRelease.text())
    }

    FileView {
        id: _uptimeFile
        path: "/proc/uptime"
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: {
            const p = _uptimeFile.text().trim().split(/\s+/)
            if (p.length > 0) root._uptimeSecs = parseFloat(p[0]) || 0
        }
    }

    Timer {
        interval: 30000; repeat: true
        running: root.active
        onTriggered: _uptimeFile.reload()
    }

    property bool _oneShotStarted: false
    property bool _compositorRead: false
    function _startOneShots(): void {
        if (!root._oneShotStarted) {
            root._oneShotStarted = true
            _kernelProc.exec(["uname", "-r"])
            _hostProc.exec(["hostname"])
        }
        // SystemTools' own tool probe is async and may still be running the first
        // time this section opens (a cold-start race, not a repeat visit); latching
        // only on a positive read — never on having merely asked once — means a
        // probe that resolves after this fires still gets picked up below instead
        // of leaving the compositor line stuck on bare "Hyprland" for the session
        if (!root._compositorRead && !_compositorProc.running && SystemTools.hasHyprctl)
            _compositorProc.exec(["hyprctl", "version", "-j"])
    }

    onActiveChanged: {
        if (!root.active) return
        root._startOneShots()
        _uptimeFile.reload()
    }

    Connections {
        target: SystemTools
        function onReadyChanged() { if (SystemTools.ready && root.active) root._startOneShots() }
    }

    BoundedProcess {
        id: _kernelProc
        timeoutMs: 5000
        stdout: StdioCollector { id: _kernelOut }
        onExited: (code) => { if (code === 0) root.kernel = SafeText.singleLineText(_kernelOut.text, 64) }
    }
    BoundedProcess {
        id: _hostProc
        timeoutMs: 5000
        stdout: StdioCollector { id: _hostOut }
        onExited: (code) => { if (code === 0) root.hostname = SafeText.singleLineText(_hostOut.text, 64) }
    }
    // jq-free: hyprctl already emits clean JSON, so a plain JSON.parse over the
    // collected stdout is simpler than shelling out to jq for one field
    BoundedProcess {
        id: _compositorProc
        timeoutMs: 5000
        stdout: StdioCollector { id: _compositorOut }
        onExited: (code) => {
            if (code !== 0) return
            root._compositorRead = true
            try {
                const parsed = JSON.parse(_compositorOut.text)
                if (typeof parsed.version === "string")
                    root.compositorVersion = SafeText.singleLineText(parsed.version, 32)
            } catch (e) {}
        }
    }
}
