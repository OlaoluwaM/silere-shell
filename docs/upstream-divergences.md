# Upstream divergences

The standing differences between this fork and upstream, each with the
action an integration takes when they collide. Read this before importing
upstream changes; review affected entries afterward and retire anything the
integration made moot, inside the same commit. README.md owns the selection,
provenance, validation, and exceptional full-merge workflow; this file holds
the standing resolutions. The current rationale is recorded in
[ADR 0003](../adrs/0003-integrate-upstream-changes-selectively.md), which
retains the ledger protections introduced by ADR 0002.

## Default: the fork supersedes upstream

In any conflict, the fork's version wins; upstream's fixes come in where
they don't fight a fork redesign. One exception: when upstream ships its
own take on something the fork already built, stop and review it case by
case. Settle that decision before importing the conflicting implementation.

## Removed outright — keep deleted

The fork is distributed by nixos-config and never publishes releases, so
the release and distribution machinery is gone whole, and the package-
updates/self-update stack went the same way (upstream still ships and
iterates it). Imports must preserve those removals. The stack's
consumers are pruned wherever upstream grows new ones: Hooks.qml carries
no "update-available" event, probe-logic has no updater suite, and
SystemTools has no packageFamily. Resolve delete/modify conflicts under
these paths as ours, re-delete anything a merge brings back under them,
and re-prune any new consumer a merge wires up:

<!-- keep-deleted:begin -->
packaging/aur
security/update-signers
scripts/release-notes.sh
scripts/silere-update.service
scripts/silere-update.timer
scripts/update.sh
docs/releasing.md
docs/releases
docs/install.md
docs/performance.md
docs/perf-history.md
docs/scripting.md
docs/troubleshooting.md
.github/workflows
CHANGELOG.md
CONTRIBUTING.md
modules/bar/widgets/ShellUpdateWidget.qml
modules/bar/widgets/UpdatesWidget.qml
modules/menu/controls/UpdateStatusCard.qml
modules/menu/settings/SettingsUpdatesSection.qml
services/ShellUpdate.qml
services/Updates.qml
modules/bar/widgets/MediaVisualizer.qml
release.json
scripts/silere
scripts/doctor.sh
scripts/test-update.sh
<!-- keep-deleted:end -->

ci-lint enforces the list: a path here that exists again fails the gate,
so resurrecting one on purpose means removing its line in the same commit.
`.github/workflows` covers all Actions — the gates run locally only.

## Shared files — union, with contracts

- `config/GeneratedDefaults.qml`: take upstream's defaults wholesale, then
  re-append the fork's added keys. The settings contract (AGENTS.md) must
  hold after the merge, and key-set changes tie the merge to nixos-config
  per README.md's coupling rule.
- `services/ShellSettings.qml`: fork-added properties and `_schema` rows
  merge as a union with upstream's.
- `qmldir` files, `BarContent`'s widget registry, `barWidgetMeta`, and the
  zone-order defaults: unions — keep both sides' entries.

## Feature collisions — standing resolutions

- Bar hover tooltips remain enabled and configurable. Keep `BarHintState`,
  `BarHintPopup`, the popup host, and every widget's hint bindings together.
  The retained popup must also take compatible upstream idle-settle fixes,
  including cancellation of its pending startup frame.
- Palette changes keep the fork's central `MatugenTheme` transition and its
  leaf-fade gate. Do not introduce upstream's parallel `PaletteFade` mechanism
  or replace the fork's glass and control tokens with upstream's palette.
- Sound keeps the fork's audio service, sound settings, privacy widget, and
  `audio` IPC contract. Do not add a second microphone widget or replace its
  controls with `PwVolumeControl`; compatible device and lifecycle fixes can
  be adapted without changing those interfaces.
- Dynamic workspaces keep the fork's occupied-workspace list and trailing
  empty workspace, up to workspace ID 15. Dynamic bar scrolling wraps within
  IDs 1–15 in both directions and skips IDs owned by another output. Bound
  enumeration before building the delegate model, including when external
  compositor shortcuts select higher IDs. Those shortcuts remain compositor-owned.
  Upstream's slot/app-model extraction must not replace
  those semantics or its marker behavior as a side effect of an import.
  Shared bump helpers may replace the matching gestures while retaining the
  fork's separate workspace entry animation; do not add upstream's slot-swap
  fade as part of that consolidation.
  Bump retriggering preserves the current value. Keep gate cleanup explicit
  through `retire()`; upstream's reset-on-stop handler causes a jump during
  rapid marker retriggering because `restart()` first stops the animation.
  Menu access must remain available when compositor workspace data is not
  ready, without requesting workspace activation or a marker pulse.
- Night light keeps the systemd service backend and the lock action keeps
  its existing provider selection. Additional upstream provider settings
  require a separate decision with their backend and UI consumers.
- The floating OSD keeps its height and slide transitions. Shared bump
  consolidation applies to the bar OSD's existing nudge without adding
  upstream's floating OSD bump to the fork.
- Settings keep backups before reset and migration, backup permission
  hardening, locked widget-order scrubbing, and future-version preservation.
  Ordered migrations may replace legacy transforms without removing those
  protections; migration output is written only after successful loading and
  backup. A failed migration backup blocks all settings writes, including
  queued edits and reload teardown, while that legacy source remains loaded.
  Retrying identical backup text must reach disk; an external replacement
  invalidates the previous save cache and follows the normal load policy.
- Menu pages restore retention for the active tab whenever the menu reopens.
  A hover-warmed window can survive its close grace after releasing that page;
  reopening the same tab must rebuild it even when the tab id has not changed.
- Notifications keep the fork's `ExpandableBody` interaction and the popup
  layer's constant screen-sized height. Take upstream delivery features such
  as grouping, inline replies, batch retirement, and sender-image hardening
  around those two constraints. The history page's stacked runs are the
  fork's own: an upstream history grouping lands under that fold or not at all.
  Expansion belongs to a run's retained oldest entry, including its timestamp,
  rather than its ordinal among the day's runs. Removing an older run must not
  transfer expansion to another run; a merged run keeps its oldest entry's state.
  The fork's duration-picker DND replaces
  upstream's scheduled quiet hours; keep `dndSchedule`, `dndFrom`, `dndTo`,
  their settings rows, and their service logic removed. Notification history
  retains `sessionCurrent` through `PersistentProperties`, which survives QML
  reloads but not process exits. Restore on its `loaded` signal, before the
  server re-emits kept notifications; defer pruning until those arrivals have
  rebuilt the live list, including cleanup triggered by settings changes.
  Until settings are ready, restore and trim against the schema maximum;
  apply the configured limit and retention only after the settings read.
  Keep the settings label scoped to reloads and the
  unused `ConfigStore` hardening for `quickshell/states.json` removed: this
  storage path writes no file. Disk persistence needs a separate decision.
- The Bluetooth bar widget stays an actionable `StatusActionPill` that opens
  the configured manager. Take compatible upstream service, accessibility,
  hint, and lifecycle improvements without replacing it with a passive pill.
  Details selection clears on the device's connection event; clearing it from
  the derived expanded-state handler creates a binding loop on disconnect.
- Power profiles keep the command backend and its `asusctl` fallback. Take
  backend-neutral upstream fixes, but do not replace this with a UPower-only
  implementation because the deploying machine runs `asusd`.
- The fork's media card lives at `modules/menu/controls/MediaCard.qml` and its
  redesign wins. Never restore the obsolete `modules/menu/MediaCard.qml` path;
  port compatible upstream privacy and metadata fixes into the controls file.
  Only an open media host may advance the shared artwork candidate after a
  load failure; a closed card retained during its exit must not change it.
- The Cava audio visualizer stays removed, including its bar placements, process
  and profile management, settings, fullscreen demand, and underline glow.
  Compatible media fixes must preserve playback controls and track progress
  without restoring the visualizer or its tool dependency.
- Control popups keep one exclusive `OverlayCoordinator` claim: menu, calendar,
  tray menu/list, quick actions, keybinds, wallpapers, and media all close their
  peers and reject late opens while idle or in overview. Any upstream popup or
  open-path change joins both `_claim()` and `_opened()`; retain the existing
  tray-list child exception for a popup-sourced tray context menu.

## What belongs here

An entry exists only where an upstream import could go wrong non-obviously: a
removal, a shared-file policy, or the feature-collision default above.
Fork-only features never get entries — new files don't conflict, and their
hooks into shared files are already covered by the union entries. A commit
that creates, changes, or moots a divergence updates this file in the same
commit; there are no batch cleanups.
