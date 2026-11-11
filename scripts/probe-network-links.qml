import QtQuick
import Quickshell
import Quickshell.Io
import "services"

// the stand-in ip and nmcli on PATH are the only commands Network's VPN detection can reach;
// this probe feeds the watcher lines through a file the stand-in ip follows, and counts the
// interface reads and the nmcli runs they lead to
ShellRoot {
    id: root

    readonly property string base: Quickshell.env("SILERE_LINKS_PROBE_ROOT")
    readonly property string wifiNotice: "2: wlp55s0: <BROADCAST,MULTICAST,UP,LOWER_UP> \\    link/ether "
    readonly property string loGone: "Deleted 1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default \\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00"
    readonly property string loBack: "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default \\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00"

    property int step: 0
    property int waited: 0
    property int paused: 0
    property int streamed: 0
    property int checks: 0
    property int failures: 0
    property bool done: false

    // a read replaces the whole counter map with finite counts; a deletion only voids entries
    property int reads: 0
    property double lastReadMs: 0
    property double sentMs: 0
    property double staleMs: 0
    property int readsBefore: 0
    property int listsBefore: 0
    property int addrsBefore: 0
    property double markMs: 0

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
    function ready(ok: bool, label: string, limit: int): bool {
        if (ok) {
            root.waited = 0
            return true
        }
        if (++root.waited > limit) {
            root.check(false, label)
            root.finish()
        }
        return false
    }
    // holds a step for a number of ticks
    function hold(ticks: int): bool {
        if (++root.paused < ticks) return false
        root.paused = 0
        return true
    }

    function calls(word: string): int {
        _nmcliCalls.reload()
        return _nmcliCalls.text().split("\n").filter(l => l === word).length
    }
    function mark(): void {
        root.readsBefore = root.reads
        root.listsBefore = root.calls("list")
        root.addrsBefore = root.calls("addr")
        root.markMs = Date.now()
    }
    function newReads(): int { return root.reads - root.readsBefore }
    function newLists(): int { return root.calls("list") - root.listsBefore }
    function newAddrs(): int { return root.calls("addr") - root.addrsBefore }

    function send(lines: var): void {
        root.sentMs = Date.now()
        Quickshell.execDetached(["sh", "-c", 'f=$1; shift; printf "%s\\n" "$@" >> "$f"', "send",
            root.base + "/ip-events"].concat(lines))
    }
    function setFile(name: string, text: string): void {
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$2" > "$1"', "set", root.base + "/" + name, text])
    }

    Connections {
        target: Network
        function on_InterfaceRxChanged() {
            const rx = Network._interfaceRx
            for (const name in rx) if (!Number.isFinite(rx[name])) return
            root.reads++
            root.lastReadMs = Date.now()
        }
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
    }

    FileView { id: _nmcliCalls; path: root.base + "/nmcli-calls"; blockAllReads: true; printErrors: false }
    FileView { id: _ipStarts; path: root.base + "/ip-starts"; blockAllReads: true; printErrors: false }

    Timer {
        id: _ticks
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            switch (root.step) {
            case 0:
                // the tool scan finds both stand-ins, the watcher is up and the first listing
                // has read the tunnel and its address
                if (!root.ready(ShellSettings.ready && SystemTools.ready && SystemTools.hasIp
                        && SystemTools.hasNmcli && Network._vpnWanted && Network._linkWatcherProcess.running
                        && Network.hasVpn && Network.vpnAddress === "10.66.0.2",
                        "the stand-ins are found, the watcher runs and the first listing lands", 200))
                    return
                // the settle and startup reads finish before anything is counted
                if (!root.hold(40)) return
                root.check(Network._watcherHealthy, "a running watcher reads as healthy")
                root.mark()
                break
            case 1:
                // the 5s poll would have read at least once by now
                if (!root.hold(65)) return
                root.check(root.newReads() === 0 && root.newLists() === 0,
                    "a healthy watcher stretches the poll: no read in 6.5s without an event (" + root.newReads() + " reads)")
                root.mark()
                root.send([root.wifiNotice])
                break
            case 2:
                if (!root.ready(root.newReads() > 0, "a link event leads to a read", 30)) return
                console.log("PROBE-LINKS event to read " + (root.lastReadMs - root.sentMs) + " ms")
                root.check(root.lastReadMs - root.sentMs < 1000, "the read follows the event within a second")
                break
            case 3:
                // past the 5s the read holds later events back for
                if (!root.hold(60)) return
                root.check(root.newReads() === 1 && root.newLists() === 0 && root.newAddrs() === 0
                        && !Network._vpnAddressStale,
                    "an event that changes nothing reads once and runs no nmcli")
                // the tunnel is rebuilt under its own name and comes back with a new address
                root.setFile("nm-address", "10.66.0.9/32")
                root.mark()
                root.staleMs = 0
                root.send([root.loGone, root.loBack])
                break
            case 4:
                if (!root.ready(root.newReads() > 0 && Network.vpnAddress === "10.66.0.9",
                        "a deletion leads to a read and a reread address", 40))
                    return
                root.check(root.staleMs > 0 && root.staleMs <= root.lastReadMs,
                    "the deletion marks the address before the read")
                console.log("PROBE-LINKS deletion to new address " + (Date.now() - root.sentMs) + " ms")
                break
            case 5:
                // past the settle listing and the read's hold
                if (!root.hold(60)) return
                root.check(root.newReads() === 1 && root.newLists() === 2 && root.newAddrs() === 2
                        && !Network._vpnAddressStale,
                    "a same-name rebuild reads once, lists twice with its settle, rereads the address twice and clears the mark ("
                        + root.newReads() + "/" + root.newLists() + "/" + root.newAddrs() + ")")
                root.mark()
                {
                    const quiet = []
                    for (let i = 0; i < 200; i++) quiet.push(i % 2 ? root.wifiNotice
                        : "9: veth9@if8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default \\    link/ether 02:00:00:00:00:09 brd ff:ff:ff:ff:ff:ff link-netnsid 0")
                    root.send(quiet)
                }
                break
            case 6:
                if (!root.hold(60)) return
                console.log("PROBE-LINKS quiet burst of 200: " + root.newReads() + " reads, "
                    + root.newLists() + " listings")
                root.check(root.newReads() === 1 && root.newLists() === 0 && root.newAddrs() === 0,
                    "a burst of 200 events that change nothing reads once and runs no nmcli")
                root.mark()
                {
                    const rebuilds = []
                    for (let i = 0; i < 100; i++) rebuilds.push(root.loGone, root.loBack)
                    root.send(rebuilds)
                }
                break
            case 7:
                if (!root.hold(60)) return
                console.log("PROBE-LINKS deleting burst of 200: " + root.newReads() + " reads, "
                    + root.newLists() + " listings, " + root.newAddrs() + " address reads")
                root.check(root.newReads() === 1 && root.newLists() === 2 && root.newAddrs() === 2,
                    "a burst of 200 deleting events reads once, lists twice with its settle and rereads the address twice")
                root.mark()
                root.streamed = 0
                break
            case 8:
                // one event a second for ten seconds: read half a second after the first, then
                // at most every 5s, the poll's own pace
                if (root.paused === 0 && root.streamed < 10) {
                    root.streamed++
                    root.send([root.wifiNotice])
                }
                if (!root.hold(10)) return
                if (root.streamed < 10) return
                break
            case 9:
                if (!root.hold(5)) return
                console.log("PROBE-LINKS stream of one event a second for 10s: " + root.newReads() + " reads")
                root.check(root.newReads() >= 2 && root.newReads() <= 3 && root.newLists() === 0,
                    "a stream of events reads no more often than every 5s (" + root.newReads() + " reads)")
                // idle: the poll and the reads stop, the watcher keeps listening
                Idle.isIdle = true
                root.mark()
                root.staleMs = 0
                break
            case 10:
                if (!root.hold(3)) return
                root.send([root.wifiNotice, root.loGone, root.loBack])
                break
            case 11:
                if (!root.hold(15)) return
                root.check(Network._linkWatcherProcess.running && root.newReads() === 0 && root.newLists() === 0
                        && root.newAddrs() === 0 && Network._vpnAddressStale && root.staleMs > 0,
                    "while idle the watcher still marks a deletion but nothing reads or runs nmcli")
                root.mark()
                Idle.isIdle = false
                break
            case 12:
                if (!root.ready(root.newReads() > 0 && root.newLists() > 0 && root.newAddrs() > 0,
                        "waking reads the list and rereads a marked address", 30))
                    return
                console.log("PROBE-LINKS wake to read " + (root.lastReadMs - root.markMs) + " ms")
                root.check(root.lastReadMs - root.markMs < 300, "waking reads the list at once")
                break
            case 13:
                if (!root.hold(45)) return
                // the watcher fails from here on: killed, then refused on every start
                root.setFile("ip-mode", "fail")
                break
            case 14:
                if (!root.hold(3)) return
                root.mark()
                Quickshell.execDetached(["sh", "-c", 'kill -KILL "$(tail -n 1 "$1" | cut -d " " -f 2)"', "kill",
                    root.base + "/ip-starts"])
                break
            case 15:
                if (!root.ready(!Network._linkWatcherProcess.running, "the killed watcher stops", 20)) return
                root.check(!Network._watcherHealthy, "a stopped watcher is not healthy")
                break
            case 16:
                if (!root.ready(Network._linkWatcherProcess.gaveUp, "a watcher whose ip exits 1 gives up", 120)) return
                _ipStarts.reload()
                root.check(_ipStarts.text().split("\n").filter(l => l.length > 0).length >= 2,
                    "the supervisor respawned the killed watcher before giving up")
                root.mark()
                break
            case 17:
                // the 5s poll is back: two reads in 11s
                if (!root.hold(110)) return
                console.log("PROBE-LINKS fallback reads in 11s: " + root.newReads())
                root.check(root.newReads() === 2 && root.newLists() === 0,
                    "without the watcher the poll reads every 5s and changes nothing (" + root.newReads() + " reads)")
                // ip gone from the next tool scan, then back
                root.setFile("ip-mode", "watch")
                SystemTools._tools = Object.assign({}, SystemTools._tools, { ip: false })
                break
            case 18:
                if (!root.hold(3)) return
                root.check(!SystemTools.hasIp && !Network._linkWatcherProcess.running && !Network._watcherHealthy,
                    "without ip there is no watcher")
                SystemTools._tools = Object.assign({}, SystemTools._tools, { ip: true })
                root.mark()
                break
            case 19:
                if (!root.ready(Network._linkWatcherProcess.running && root.newReads() > 0,
                        "a scan that finds ip again starts the watcher, which reads at once", 30))
                    return
                root.check(Network._watcherHealthy, "the restarted watcher is healthy")
                root.finish()
                return
            }
            root.step++
        }
    }
}
