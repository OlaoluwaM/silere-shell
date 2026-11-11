import QtQuick
import Quickshell
import Quickshell.Io
import "services"

// the stand-in ip and nmcli on PATH are the only commands Network's VPN detection can reach;
// this probe feeds the watcher lines through a file the stand-in ip follows, and counts the
// interface reads and the nmcli runs they lead to. The service's timers run about ten times
// faster here once their shipped values have been checked; the stretched poll only has to
// outlast the run.
ShellRoot {
    id: root

    readonly property string base: Quickshell.env("SILERE_LINKS_PROBE_ROOT")
    readonly property string wifiNotice: "2: wlp55s0: <BROADCAST,MULTICAST,UP,LOWER_UP> \\    link/ether "
    readonly property string loGone: "Deleted 1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default \\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00"
    readonly property string loBack: "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default \\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00"
    readonly property string vethUp: "9: veth9@if8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default \\    link/ether 02:00:00:00:00:09 brd ff:ff:ff:ff:ff:ff link-netnsid 0"

    property int step: 0
    property double stepMs: 0
    property double waitedFrom: 0
    property int checks: 0
    property int failures: 0
    property bool done: false

    property var readTimes: []
    property double markMs: 0
    property int readsBefore: 0
    property int listsBefore: 0
    property int addrsBefore: 0
    property double staleMs: 0
    property int streamed: 0
    property bool switched: false
    property double watcherStartMs: 0

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    function finish(): void {
        if (root.done) return
        root.done = true
        _ticks.stop()
        console.log("PROBE-LINKS " + (root.failures ? "failed " : "passed ") + root.checks + " checks")
    }

    // holds a step until its condition lands; a condition that never lands fails the run
    function ready(ok: bool, label: string, limitMs: int): bool {
        if (ok) return true
        if (Date.now() - root.stepMs > limitMs) {
            root.check(false, label)
            root.finish()
        }
        return false
    }
    function held(ms: int): bool {
        return Date.now() - root.stepMs >= ms
    }

    function calls(word: string): int {
        _nmcliCalls.reload()
        return _nmcliCalls.text().split("\n").filter(l => l === word).length
    }
    function mark(): void {
        root.readsBefore = root.readTimes.length
        root.listsBefore = root.calls("list")
        root.addrsBefore = root.calls("addr")
        root.markMs = Date.now()
    }
    function newReads(): int { return root.readTimes.length - root.readsBefore }
    function newLists(): int { return root.calls("list") - root.listsBefore }
    function newAddrs(): int { return root.calls("addr") - root.addrsBefore }
    function counts(): string {
        return root.newReads() + " reads, " + root.newLists() + " listings, " + root.newAddrs() + " address reads"
    }

    // a line starting "ERR " reaches the watcher on stderr
    function send(lines: var): void {
        Quickshell.execDetached(["sh", "-c", 'f=$1; shift; printf "%s\\n" "$@" >> "$f"', "send",
            root.base + "/ip-events"].concat(lines))
    }
    function setFile(name: string, text: string): void {
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$2" > "$1"', "set", root.base + "/" + name, text])
    }
    function setIp(present: bool): void {
        SystemTools._tools = Object.assign({}, SystemTools._tools, { ip: present })
    }

    Connections {
        target: Network
        function on_InterfaceRxChanged() { root.readTimes = root.readTimes.concat([Date.now()]) }
        function on_VpnAddressStaleChanged() {
            if (Network._vpnAddressStale) root.staleMs = Date.now()
        }
    }

    // the session starts active, and steps below take it idle and back. NetworkManager may be
    // out of reach from the probe's namespace, so the device model is held available, as it
    // is on a connected desktop
    Component.onCompleted: {
        Idle.isIdle = false
        Network.available = true
        root.stepMs = Date.now()
    }

    Connections {
        target: Network._linkWatcherProcess
        function onRunningChanged() {
            if (Network._linkWatcherProcess.running) root.watcherStartMs = Date.now()
        }
    }

    FileView { id: _nmcliCalls; path: root.base + "/nmcli-calls"; blockAllReads: true; printErrors: false }
    FileView { id: _ipStarts; path: root.base + "/ip-starts"; blockAllReads: true; printErrors: false }

    Timer {
        id: _ticks
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            const watcher = Network._linkWatcherProcess
            switch (root.step) {
            case 0:
                // the tool scan finds both stand-ins, the watcher is up and the first listing
                // has read the tunnel and its address
                if (!root.ready(ShellSettings.ready && SystemTools.ready && SystemTools.hasIp
                        && SystemTools.hasNmcli && Network._vpnWanted && watcher.running
                        && Network.hasVpn && Network.vpnAddress === "10.66.0.2",
                        "the stand-ins are found, the watcher runs and the first listing lands", 20000))
                    return
                root.check(Network._watcherHealthy && Network._interfacePollTimer.interval === 120000
                        && Network._linkBurstTimer.interval === 500 && Network._linkCooldownTimer.interval === 5000
                        && Network._vpnSettleTimer.interval === 3000 && Network._vpnRebuildCheckTimer.interval === 9000
                        && watcher.restartDelay === 5000,
                    "the shipped timings: 120s poll with a healthy watcher, 500ms burst, 5s hold, 3s settle, 9s late reread, 5s respawn")
                root.setIp(false)
                break
            case 1:
                if (!root.ready(!watcher.running, "a scan without ip stops the watcher", 2000)) return
                root.check(!Network._watcherHealthy && Network._interfacePollTimer.interval === 5000,
                    "without ip the poll is back at 5s")
                Network._linkBurstTimer.interval = 50
                Network._linkCooldownTimer.interval = 500
                Network._vpnSettleTimer.interval = 300
                Network._vpnRebuildCheckTimer.interval = 900
                watcher.restartDelay = 300
                Network._interfacePollTimer.interval = Qt.binding(() => Network._watcherHealthy ? 60000 : 500)
                root.mark()
                break
            case 2:
                if (!root.held(1200)) return
                root.check(root.newReads() >= 2 && root.newLists() === 0,
                    "without ip the poll reads at its own pace and changes nothing (" + root.counts() + ")")
                root.watcherStartMs = 0
                root.setIp(true)
                root.mark()
                break
            case 3: {
                // the start read, then one after ip has opened its socket
                if (!root.ready(watcher.running && root.watcherStartMs > 0 && root.held(400),
                        "the watcher starts again with ip", 2000))
                    return
                const times = root.readTimes.filter(t => t >= root.watcherStartMs)
                    .map(t => t - root.watcherStartMs)
                root.check(Network._watcherHealthy && times.length === 2 && times[0] < 40 && times[1] >= 45,
                    "a watcher start reads at once and again a burst later (" + times.join(", ") + " ms)")
                break
            }
            case 4:
                if (!root.held(600)) return
                root.mark()
                break
            case 5:
                // the 0.5s poll would have read twice by now
                if (!root.held(1100)) return
                root.check(root.newReads() === 0 && root.newLists() === 0,
                    "a healthy watcher stretches the poll (" + root.counts() + ")")
                root.mark()
                root.send([root.wifiNotice])
                break
            case 6:
                if (!root.ready(root.newReads() > 0, "a link event leads to a read", 1000)) return
                console.log("PROBE-LINKS event to read " + (root.readTimes[root.readTimes.length - 1] - root.markMs)
                    + " ms at a 50 ms burst")
                break
            case 7:
                if (!root.held(600)) return
                root.check(root.newReads() === 1 && root.newLists() === 0 && root.newAddrs() === 0
                        && !Network._vpnAddressStale,
                    "an event that changes nothing reads once and runs no nmcli (" + root.counts() + ")")
                // the tunnel is rebuilt under its own name, its new address already handed out
                root.setFile("nm-address", "10.66.0.9/32")
                root.mark()
                root.staleMs = 0
                root.send([root.loGone, root.loBack])
                break
            case 8:
                if (!root.ready(root.newReads() > 0 && Network.vpnAddress === "10.66.0.9",
                        "a deletion leads to a read and a reread address", 1000))
                    return
                root.check(root.staleMs > 0 && root.staleMs <= root.readTimes[root.readTimes.length - 1],
                    "the deletion marks the address before the read")
                break
            case 9:
                // past the settle listing and the late reread
                if (!root.held(1400)) return
                root.check(root.newReads() === 1 && root.newLists() === 2 && root.newAddrs() === 3
                        && !Network._vpnAddressStale,
                    "a same-name rebuild reads once, lists twice, rereads the address three times and clears the mark ("
                        + root.counts() + ")")
                // rebuilt again, and NetworkManager hands out the address only after the settle reread
                root.mark()
                root.switched = false
                root.send([root.loGone, root.loBack])
                break
            case 10:
                if (!root.switched && root.held(650)) {
                    root.setFile("nm-address", "10.66.0.10/32")
                    root.switched = true
                }
                if (!root.held(1500)) return
                console.log("PROBE-LINKS late address: " + Network.vpnAddress + " after " + root.counts())
                root.check(Network.vpnAddress === "10.66.0.10" && !Network._vpnAddressStale,
                    "an address handed out after the settle reread still reaches the bar")
                root.mark()
                {
                    const quiet = []
                    for (let i = 0; i < 200; i++) quiet.push(i % 2 ? root.wifiNotice : root.vethUp)
                    root.send(quiet)
                }
                break
            case 11:
                if (!root.held(600)) return
                console.log("PROBE-LINKS quiet burst of 200: " + root.counts())
                root.check(root.newReads() === 1 && root.newLists() === 0 && root.newAddrs() === 0,
                    "a burst of 200 events that change nothing reads once and runs no nmcli")
                root.mark()
                {
                    const rebuilds = []
                    for (let i = 0; i < 100; i++) rebuilds.push(root.loGone, root.loBack)
                    root.send(rebuilds)
                }
                break
            case 12:
                if (!root.held(1400)) return
                console.log("PROBE-LINKS deleting burst of 200: " + root.counts())
                root.check(root.newReads() === 1 && root.newLists() === 2 && root.newAddrs() === 3,
                    "a burst of 200 deleting events costs what one deletion does")
                root.mark()
                root.streamed = 0
                break
            case 13:
                // one event every 100ms for a second: read a burst after the first, then no more
                // often than the hold allows
                if (root.streamed < 10 && root.held(root.streamed * 100)) {
                    root.streamed++
                    root.send([root.wifiNotice])
                }
                if (!root.held(1100)) return
                console.log("PROBE-LINKS stream of one event every 100 ms for 1 s: " + root.newReads() + " reads")
                root.check(root.newReads() >= 2 && root.newReads() <= 3 && root.newLists() === 0,
                    "a stream of events reads no more often than the hold allows (" + root.newReads() + " reads)")
                break
            case 14:
                if (!root.held(600)) return
                root.mark()
                root.staleMs = 0
                root.send(["ERR netlink receive error No buffer space available (105)"])
                break
            case 15:
                if (!root.ready(root.newReads() > 0 && root.newLists() > 0,
                        "an overrun notice on stderr leads to a read and a recheck", 1000))
                    return
                root.check(root.staleMs > 0 && watcher.running,
                    "an overrun marks the address and the watcher carries on")
                break
            case 16:
                if (!root.held(1400)) return
                // idle: the poll and the reads stop, the watcher keeps listening
                Idle.isIdle = true
                root.mark()
                root.staleMs = 0
                root.send([root.wifiNotice, root.loGone, root.loBack])
                break
            case 17:
                if (!root.held(400)) return
                root.check(watcher.running && root.newReads() === 0 && root.newLists() === 0
                        && root.newAddrs() === 0 && Network._vpnAddressStale && root.staleMs > 0,
                    "while idle the watcher still marks a deletion but nothing reads or runs nmcli")
                root.mark()
                Idle.isIdle = false
                break
            case 18:
                if (!root.ready(root.newReads() > 0 && root.newLists() > 0 && root.newAddrs() > 0,
                        "waking reads the list and rereads a marked address", 1000))
                    return
                console.log("PROBE-LINKS wake to read " + (root.readTimes[root.readsBefore] - root.markMs) + " ms")
                root.check(root.readTimes[root.readsBefore] - root.markMs < 100, "waking reads the list at once")
                break
            case 19:
                if (!root.held(1400)) return
                // the watcher fails from here on: killed, then refused on every start
                root.setFile("ip-mode", "fail")
                break
            case 20:
                if (!root.held(100)) return
                Quickshell.execDetached(["sh", "-c", 'kill -KILL "$(tail -n 1 "$1" | cut -d " " -f 2)"', "kill",
                    root.base + "/ip-starts"])
                break
            case 21:
                if (!root.ready(watcher.gaveUp, "a watcher whose ip exits 1 gives up after a respawn", 3000)) return
                _ipStarts.reload()
                root.check(!Network._watcherHealthy
                        && _ipStarts.text().split("\n").filter(l => l.length > 0).length >= 3,
                    "the supervisor respawned the killed watcher before giving up")
                break
            case 22:
                // the respawn's own reads settle first
                if (!root.held(200)) return
                root.mark()
                break
            case 23:
                if (!root.held(1200)) return
                console.log("PROBE-LINKS fallback reads in 1.2 s at a 0.5 s poll: " + root.newReads())
                root.check(root.newReads() >= 2 && root.newReads() <= 3 && root.newLists() === 0,
                    "a watcher that gave up leaves the poll at its own pace (" + root.counts() + ")")
                root.finish()
                return
            }
            root.step++
            root.stepMs = Date.now()
        }
    }
}
