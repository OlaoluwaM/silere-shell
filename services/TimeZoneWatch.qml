pragma Singleton

// FileView watches a symlink's target, not the link itself, so an atomic
// /etc/localtime swap (systemd-timedated, a NixOS rebuild) never reaches it;
// watch the containing directory instead, since the rename lands there. A
// fresh Date() reflects the swap immediately (tzset re-reads it on each call);
// SystemClock.date does not -- it holds its last tick's wall time until the
// next one, so consumers must re-derive from a new Date(), not clock.date.

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    signal switched()

    property string _zone: ""
    property bool   _known: false

    // pure so probe-logic can pin the zoneinfo-path parsing down without a live symlink
    function zoneFromLink(target: string): string {
        const t = String(target || "").trim()
        if (t.length === 0) return ""
        const marker = "zoneinfo/"
        const at = t.lastIndexOf(marker)
        if (at >= 0) return t.slice(at + marker.length)
        return t.indexOf("/") < 0 ? t : ""
    }

    // a collision queues rather than drops, same as NightLight._checkActive()
    property bool _resolvePending: false
    function _resolve(): void {
        if (_resolveProc.running) { root._resolvePending = true; return }
        _resolveProc.exec(["readlink", "/etc/localtime"])
    }

    BoundedProcess {
        id: _resolveProc
        timeoutMs: 5000
        stdout: StdioCollector { id: _resolveOut }
        onExited: (code) => {
            const rerun = root._resolvePending
            root._resolvePending = false
            // an unreadable link is transient noise, not a zone -- never compare against it
            if (!_resolveProc.timedOut && code === 0) {
                const next = root.zoneFromLink(_resolveOut.text)
                if (!root._known) {
                    root._known = true
                    root._zone = next
                } else if (next !== root._zone) {
                    root._zone = next
                    Date.timeZoneUpdated()
                    root.switched()
                }
            }
            if (rerun) root._resolve()
        }
    }

    SupervisedProcess {
        id: _watcher
        superviseWhen: SystemTools.ready && SystemTools.hasInotifywait
        restartDelay: 5000
        command: ["inotifywait", "-m", "-q", "-e", "moved_to,create", "--include", "/localtime$", "/etc"]
        stdout: SplitParser {
            onRead: line => _debounce.restart()
        }
        // a swap during the restart backoff still lands here as a same-zone or
        // real-change resolve, same restat-on-restart idiom Recording.qml uses
        onRunningChanged: if (running) root._resolve()
    }

    // a swap can print more than one matching line; settle before resolving once
    Timer {
        id: _debounce
        interval: 400
        repeat: false
        onTriggered: root._resolve()
    }
}
