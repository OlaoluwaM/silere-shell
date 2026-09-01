# Upstream v0.9.0 merge resolution record

Commit `813469b` merges upstream v0.9.0 (`78fb1ea`) into the fork at
`a4ecf7e`. The merge commit kept only its subject, so this document records
the resolution narrative that normally lives in the merge message.

## What came in

The merge takes upstream's notification grouping, inline replies, batch
retirement, sender-image hardening, and history-row recycling. It also takes
the bar hint service and popup, the self-contained window-title widget,
free-span centre-zone placement, workspace and bar lifecycle settling,
shared XDG path resolution, the Quickshell 0.3.1 floor, and the expanded
probe and lint suites.

## Resolutions

- Release, updater, packaging, and distribution paths stayed deleted. New
  consumers in Hooks, SystemTools, settings, and probes were pruned with
  them, and the keep-deleted block was extended to cover every path upstream
  added or changed.
- Notifications kept the fork's shared `ExpandableBody` interaction and
  screen-sized popup layer. Upstream grouping, replies, batch retirement,
  sender-image safety, and recycled history rows were fitted around those
  constraints. The fork's duration-picker DND continued to replace
  upstream quiet hours.
- The fork's actionable Bluetooth pill stayed in place while compatible
  upstream service, hint, accessibility, and lifecycle changes came in.
- Power profiles kept the command backend and `asusctl` fallback. Only
  backend-neutral lifecycle changes were adopted from upstream's UPower
  implementation.
- The fork's Wi-Fi details and list-freeze implementation stayed in place;
  upstream's signal-drift fix was already covered by that model.
- The redesigned media card remained under `modules/menu/controls`, with
  upstream's private-tab masking and compatible metadata fixes ported into
  it.
- Upstream's window-title widget and centre-zone work were adopted while the
  fork kept gap-centering enabled by default and carried the renamed setting
  through its migration path.
- Shared registries, `qmldir` files, bar widget metadata, settings properties,
  and schema rows were merged as unions. `GeneratedDefaults.qml` kept stock
  defaults, and the shell-to-Nix settings contract finished at 52 keys on
  each side.

## Post-merge corrections

The first review pass found several compatible fixes that the conflict pass
had missed. The follow-up commits restored spaceless notification wrapping
(`4c478ea`), gated the package repair hint (`c494ffc`), restored the retained
power backend's probes and surface-open refreshes (`6e5a6c4`), recorded the
quiet-hours replacement (`ff375f8`), completed bar hints and spoken vitals
(`77b6327`), and removed stale Bluetooth and forking leftovers (`3b53427`,
`11760ea`).
