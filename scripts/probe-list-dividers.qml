pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "services"
import "modules/menu"
import "modules/menu/controls"

// A card's divider beside a picker answers to the picker's list: it fades while the list's
// first or last row shows its band against it, as it does beside a hovered card row, and
// comes back once that row is scrolled off the line or loses its fill. The real WifiList,
// fed rows through Network.wifiNetworks, in a real offscreen window, since a list only
// builds its rows inside a window's polish loop
ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0
    property int phase: 0
    property bool reduceMotionWas: false

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    function networks(count: int, active: int): var {
        const rows = []
        for (let i = 0; i < count; i++)
            rows.push({ ssid: "net" + i, label: "net" + i, glyph: "󰤨", secured: true,
                psk: true, profileOnly: false, active: i === active, known: true })
        return rows
    }

    // the same networks in a new order, as Network's sort republishes them when one connects
    function ordered(names, active: string): var {
        return names.map(name => ({ ssid: name, label: name, glyph: "󰤨", secured: true,
            psk: true, profileOnly: false, active: name === active, known: true }))
    }

    function findList(item): var {
        if (!item) return null
        if (item.scrollable !== undefined && item.delegate !== undefined && item.model !== undefined)
            return item
        for (let i = 0; i < item.children.length; i++) {
            const found = root.findList(item.children[i])
            if (found) return found
        }
        return null
    }

    // reduce motion lands each fade at once, so a line's _fade is its settled outcome
    function faded(lines: Item, i: int): bool {
        return lines.itemAt(i)._fade === 0 && !lines.itemAt(i).visible
    }
    function kept(lines: Item, i: int): bool {
        return lines.itemAt(i)._fade === 1 && lines.itemAt(i).visible
    }

    FloatingWindow {
        visible: true
        implicitWidth: 640
        implicitHeight: 400
        color: "transparent"

        // the Wi-Fi card's shape: a header row, the picker holding the list, the next row
        Item {
            width: 300
            height: _wifiCol.height
            Column {
                id: _wifiCol
                width: parent.width
                MenuRow { height: 40 }
                InlinePicker {
                    id: picker
                    open: true
                    content: Component {
                        WifiList { width: parent.width; open: true }
                    }
                }
                MenuRow { height: 40 }
            }
            RowDividers { id: wifiLines; column: _wifiCol }
        }

        // a picker whose content keeps no edge contract: a filled first row there has never
        // faded the card's line, and still does not
        Item {
            x: 320
            width: 300
            height: _otherCol.height
            Column {
                id: _otherCol
                width: parent.width
                MenuRow { height: 40 }
                InlinePicker {
                    open: true
                    content: Component {
                        Column {
                            width: parent.width
                            InlineOptionRow { label: "selected"; selected: true }
                            InlineOptionRow { label: "plain" }
                        }
                    }
                }
                MenuRow { height: 40 }
            }
            RowDividers { id: otherLines; column: _otherCol }
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            const list = root.findList(picker)
            switch (root.phase++) {
            case 0:
                root.reduceMotionWas = ShellSettings.reduceMotion
                ShellSettings.reduceMotion = true
                break
            case 2:
                Network.wifiNetworks = root.networks(3, -1)
                break
            case 4:
                root.check(list !== null && list.count === 3 && !list.scrollable
                        && wifiLines.count === 3 && root.kept(wifiLines, 1) && root.kept(wifiLines, 2),
                    "a list of plain rows keeps the card's lines above and below it")
                root.check(otherLines.count === 3 && root.kept(otherLines, 1)
                        && root.kept(otherLines, 2),
                    "a picker without the edge contract keeps its lines beside a selected row")
                Network.wifiNetworks = root.networks(3, 0)
                break
            case 6:
                root.check(root.faded(wifiLines, 1) && root.kept(wifiLines, 2),
                    "a connected first row hides the line above the list, and only that one")
                Network.wifiNetworks = root.networks(3, 2)
                break
            case 8:
                root.check(root.kept(wifiLines, 1) && root.faded(wifiLines, 2),
                    "a connected last row hides the line below the list, and the top one returns")
                Network.wifiNetworks = root.networks(12, 0)
                break
            case 10:
                root.check(list.scrollable && list.atYBeginning && root.faded(wifiLines, 1),
                    "a list resting at its top answers to its connected first row")
                list.contentY = 40
                break
            case 11:
                root.check(!list.atYBeginning && root.kept(wifiLines, 1),
                    "the line returns once the first row is scrolled off it")
                list.contentY = 0
                break
            case 12:
                root.check(root.faded(wifiLines, 1),
                    "the line fades again with the list back at its top")
                Network.wifiNetworks = root.networks(12, -1)
                break
            case 14:
                root.check(root.kept(wifiLines, 1) && root.kept(wifiLines, 2),
                    "the line returns once the first row loses its fill")
                Network.wifiNetworks = root.networks(12, 11)
                break
            case 16:
                root.check(root.kept(wifiLines, 2),
                    "a connected last row out of view leaves the line below alone")
                list.positionViewAtEnd()
                break
            case 18:
                root.check(list.atYEnd && root.faded(wifiLines, 2) && root.kept(wifiLines, 1),
                    "scrolled to its end, the list's connected last row hides the line below")
                root.check(root.kept(otherLines, 1) && root.kept(otherLines, 2),
                    "the other card's lines never moved")
                // the same rows, kept by ssid, so a reorder moves delegates instead of rebuilding them
                Network.wifiNetworks = root.ordered(["net0", "net1", "net2"], "")
                break
            case 20:
                root.check(root.kept(wifiLines, 1) && root.kept(wifiLines, 2),
                    "a reordered list starts with both lines")
                // net2 connects and sorts to the front
                Network.wifiNetworks = root.ordered(["net2", "net0", "net1"], "net2")
                break
            case 22:
                root.check(root.faded(wifiLines, 1) && root.kept(wifiLines, 2),
                    "a network that connects and sorts to the top hides the line above it")
                // still connected, it sorts to the end: only the order changes, so the line
                // below now answers to the filled row and the line above comes back
                Network.wifiNetworks = root.ordered(["net0", "net1", "net2"], "net2")
                break
            case 24:
                root.check(root.kept(wifiLines, 1) && root.faded(wifiLines, 2),
                    "a filled row sorted to the bottom moves the fade from the top line to the bottom one")
                Network.wifiNetworks = []
                ShellSettings.reduceMotion = root.reduceMotionWas
                console.log("PROBE-LIST-DIVIDERS " + (root.failures ? "failed" : "passed")
                    + " " + root.checks + " checks")
                console.log("PROBE-LIST-DIVIDERS-DONE")
                stop()
                break
            }
        }
    }
}
