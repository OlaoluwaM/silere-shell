# Pre-commit QML review

Scope: workspace cap/wrap, overlay coordinator, related probes/fixtures, and workspace settings description. Bluetooth has its separately completed review and live retest under .debug/bluetooth-details-fix-20260910.

Python lint completed, exit 1 with findings. Changed-line diagnostics were reviewed: BND-2 flags the local JavaScript variable target; three JS-2 diagnostics match strict !== expressions. These are scanner false positives. Other diagnostics concern unchanged lines.

System qmllint completed, exit 0 with three warnings in unchanged Workspaces.qml calls through Repeater.itemAt's generic QQuickItem return type (playMarkerPass, clearMarkerPass, playNotificationPulse). The JSON reports Workspaces success=false because of these warnings; other requested files report success=true. No changed-line type finding. Probe assertions are covered by the runtime runners.

Six local analysis missions completed (not independent subagents):

1. Bindings/properties: the dynamic key reads compositor occupancy and ownership, never the app cache derived from visibleIds. Existing paging handlers do not feed into that key. The added description binding reads the imported compositor singleton. No new aliases or cycles. Result: no confirmed issue.
2. Layout/anchoring: model growth is capped before enumeration and reuses existing width/paging motion. Marker visibility guards activeIndex when an external high ID is selected. No new layout node, anchor or geometry assignment. Result: no confirmed issue.
3. Loading/lifecycle: added coordinator Connections follow existing singleton ownership. Probe-created workspace objects are destroyed after assertions, and settings are restored. Fixture replacements remain in disposable trees. Result: no confirmed issue.
4. Delegates: existing required modelData remains intact; bounded arrays feed the existing Repeater. Paging suppression and delegate retirement behavior are retained. No pooled state or new per-delegate callbacks. Result: no confirmed issue.
5. States/transitions: each new popup signal uses _opened and the shared environment guard. _claim closes peers and preserves the tray-list child exception; close events do not recursively claim ownership. Workspace navigation wraps both ways, skips foreign outputs, stops after a fully blocked cycle, and retains static/Niri paths. Result: no confirmed issue.
6. Performance/code quality: enumeration is bounded by 15, ownership lookups use the existing map, and each scroll step searches at most 15 IDs. No new timers, process polling, rendering effects or cross-module dependency. Result: no confirmed issue.

No confirmed findings or investigation targets remain in this scoped QML review. Mock Niri and synthetic coordinator coverage do not establish live compositor behavior. Generic Python lint and qmllint are not globally clean; their attributable outputs and exit statuses are retained alongside this report.
