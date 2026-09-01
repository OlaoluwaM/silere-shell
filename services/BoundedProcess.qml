import QtQuick
import Quickshell
import Quickshell.Io

Process {
    id: root

    property int timeoutMs: 0
    property bool timedOut: false

    signal timeoutReached()

    // QProcess signals only the direct child, so a bash wrapper's own children outlive it;
    // collect the tree before TERM, then signal only pids whose start time still matches
    readonly property string _terminateTreeScript:
        'root_pid=$1; grace=${2:-2}; case $root_pid in ""|*[!0-9]*) exit 0;; esac; ' +
        'pids=(); starts=(); seen=" "; ' +
        'start_of() { local line rest; { IFS= read -r line < "/proc/$1/stat"; } 2>/dev/null || return 1; ' +
        'rest=${line##*) }; set -- $rest; [ "$#" -ge 20 ] || return 1; printf "%s\\n" "${20}"; }; ' +
        'remember() { local pid=$1 start; case "$seen" in *" $pid "*) return;; esac; ' +
        'start=$(start_of "$pid") || return; seen="$seen$pid "; pids+=("$pid"); starts+=("$start"); }; ' +
        'collect() { local parent=$1 stat line pid rest ppid; for stat in /proc/[0-9]*/stat; do ' +
        '{ IFS= read -r line < "$stat"; } 2>/dev/null || continue; pid=${line%% *}; rest=${line##*) }; ' +
        'set -- $rest; ppid=${2:-}; [ "$ppid" = "$parent" ] && collect "$pid"; done; remember "$parent"; }; ' +
        'signal_saved() { local sig=$1 i current; for ((i=0; i<${#pids[@]}; i++)); do ' +
        'current=$(start_of "${pids[i]}") || continue; [ "$current" = "${starts[i]}" ] ' +
        '&& kill -s "$sig" "${pids[i]}" 2>/dev/null || true; done; }; ' +
        'root_start=$(start_of "$root_pid") || exit 0; collect "$root_pid"; signal_saved TERM; ' +
        '[ "$grace" -le 0 ] || sleep "$grace"; ' +
        'current=$(start_of "$root_pid") || current=; [ "$current" != "$root_start" ] || collect "$root_pid"; ' +
        'signal_saved KILL'

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
            const pid = root.processId
            if (pid > 0)
                Quickshell.execDetached(["bash", "-c", root._terminateTreeScript,
                    "silere-timeout", String(pid), "2"])
            else
                root.running = false
            root.timeoutReached()
        }
    }

    // retry the whole tree without another grace period if the first helper stalled
    property Timer _killGrace: Timer {
        interval: 3000
        running: root.timedOut && root.running
        onTriggered: {
            const pid = root.processId
            if (root.running && pid > 0)
                Quickshell.execDetached(["bash", "-c", root._terminateTreeScript,
                    "silere-timeout-backstop", String(pid), "0"])
        }
    }
}
