import QtQuick

QtObject {
    id: root

    required property string monitorName
    required property int activeId
    required property int effectiveWsCount
    required property bool dynamicMode
    required property bool wantNewWorkspace
    required property bool perOutputWorkspaceIds
    required property var workspaces

    // No compositor numbers a workspace 0, so it can stand for one that does not exist yet.
    readonly property int newWorkspaceId: 0
    // Beyond this the strip is wider than it is readable.
    readonly property int maxDynamicSlots: 12

    function dynamicIds(own: var, active: int, wantNew: bool, limit: int): var {
        const seen = Object.create(null)
        const ids = []
        let activeOccupied = false
        for (let i = 0; i < own.length; i++) {
            const ws = own[i]
            if (!ws || ws.wsId < 1) continue
            if (ws.wsId === active && ws.occupied) activeOccupied = true
            if (!ws.occupied && !ws.urgent && ws.wsId !== active) continue
            if (seen[ws.wsId] === true) continue
            seen[ws.wsId] = true
            ids.push(ws.wsId)
        }
        if (active > 0 && seen[active] !== true) ids.push(active)
        ids.sort(function(a, b) { return a - b })
        if (limit > 0 && ids.length > limit) {
            // Window overflow around the active cell; trimming the tail hides the one in view.
            const at = ids.indexOf(active)
            const start = at < 0 ? 0
                : Math.max(0, Math.min(ids.length - limit,
                    at - Math.floor((limit - 1) / 2)))
            ids.splice(0, start)
            ids.length = limit
        }
        // A fresh workspace is already in hand when the one in view is empty.
        if (wantNew && activeOccupied) ids.push(root.newWorkspaceId)
        return ids
    }

    // One pass feeds ownership, lookup, page anchoring and the per-output id cap.
    readonly property var workspaceIndex: {
        const owners = Object.create(null)
        const byId = Object.create(null)
        const own = []
        let first = 0
        let last = 0
        const vals = root.workspaces
        for (let i = 0; i < vals.length; i++) {
            const ws = vals[i]
            if (!ws) continue
            if (ws.output === root.monitorName) {
                byId[ws.wsId] = ws
                own.push(ws)
                if (ws.wsId > 0) {
                    first = first === 0 ? ws.wsId : Math.min(first, ws.wsId)
                    last = Math.max(last, ws.wsId)
                }
            }
            // Hyprland reports a workspace before its monitor resolves; an empty output is
            // unknown, not elsewhere, and recording it drops the id off this bar's page.
            if (!root.perOutputWorkspaceIds && ws.wsId > 0 && ws.output.length > 0)
                owners[ws.wsId] = ws.output
        }
        return { owners: owners, byId: byId, own: own, first: first, last: last }
    }
    readonly property var workspaceOwners: root.workspaceIndex.owners
    readonly property var workspaceMap: root.workspaceIndex.byId
    readonly property int monitorAnchorId: {
        let first = root.activeId > 0 ? root.activeId : 1
        if (root.workspaceIndex.first > 0)
            first = Math.min(first, root.workspaceIndex.first)
        return first
    }

    function knownOnOtherMonitor(id: int): bool {
        if (root.monitorName.length === 0) return false
        const owner = root.workspaceOwners[id]
        return owner !== undefined && owner !== root.monitorName
    }

    // Per-output ids already include one trailing empty workspace. 0 means no cap.
    readonly property int idCap: root.perOutputWorkspaceIds
        ? root.workspaceIndex.last : 0

    // Hyprland ids are global: a fixed page must skip ids owned by another output.
    readonly property string visibleIdsKey: {
        if (root.dynamicMode)
            return root.dynamicIds(root.workspaceIndex.own, root.activeId,
                root.wantNewWorkspace, root.maxDynamicSlots).join(",")
        const ids = []
        const anchor = Math.max(1, root.monitorAnchorId)
        const active = Math.max(anchor, root.activeId)
        const cap = root.idCap
        let activeLogicalIndex = 0
        for (let id = anchor; id < active; id++)
            if (!root.knownOnOtherMonitor(id)) activeLogicalIndex++
        const pageStart = Math.floor(activeLogicalIndex / root.effectiveWsCount)
            * root.effectiveWsCount
        let logicalIndex = 0
        for (let id = anchor; ids.length < root.effectiveWsCount; id++) {
            if (cap > 0 && id > cap) break
            if (root.knownOnOtherMonitor(id)) continue
            if (logicalIndex >= pageStart) ids.push(id)
            logicalIndex++
        }
        return ids.join(",")
    }
    readonly property var visibleIds: {
        if (root.visibleIdsKey.length === 0) return []
        const parts = root.visibleIdsKey.split(",")
        const ids = []
        for (let i = 0; i < parts.length; i++) {
            const id = Number(parts[i])
            if (isFinite(id)) ids.push(id)
        }
        return ids
    }

    // A Repeater over an id array rebuilds every delegate on any change. Keep stable slots.
    readonly property int slotCount: root.dynamicMode
        ? root.maxDynamicSlots + 1 : root.effectiveWsCount
    readonly property var visibleIndexById: {
        const indexes = Object.create(null)
        const ids = root.visibleIds
        for (let i = 0; i < ids.length; i++) indexes[ids[i]] = i
        return indexes
    }

    function visibleIndex(wsId: int): int {
        // A compositor signal can land mid-teardown, when the map reads back undefined.
        const byId = root.visibleIndexById
        if (!byId) return -1
        const index = byId[wsId]
        return index === undefined ? -1 : index
    }
}
