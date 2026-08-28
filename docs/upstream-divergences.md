# Upstream divergences

The standing differences between this fork and upstream, each with the
action a merge takes when they collide. Read this before starting an
upstream merge; walk it after resolving and retire anything the merge made
moot, inside the merge commit. The merge ritual itself (tags only, one
aggregate pass, the revert recipe) is README.md's; this file only holds the
resolutions. The rationale and trade-offs behind the doctrine are recorded
in ADR 0002.

## Default: the fork supersedes upstream

In any conflict, the fork's version wins; upstream's fixes come in where
they don't fight a fork redesign. One exception: when upstream ships its
own take on something the fork already built, stop and review it case by
case — that decision pauses the merge and gets made cold, never mid-
conflict.

## Removed outright — keep deleted

The fork is distributed by nixos-config and never publishes releases, so
the release and distribution machinery is gone whole, and the package-
updates/self-update stack went the same way (upstream still ships and
iterates it — the v0.8.0 merge re-deleted all six files). Resolve
delete/modify conflicts under these paths as ours, and re-delete anything
a merge brings back under them:

<!-- keep-deleted:begin -->
packaging/aur
scripts/release-notes.sh
docs/releasing.md
docs/releases
.github/workflows
CHANGELOG.md
modules/bar/widgets/ShellUpdateWidget.qml
modules/bar/widgets/UpdatesWidget.qml
modules/menu/controls/UpdateStatusCard.qml
modules/menu/settings/SettingsUpdatesSection.qml
services/ShellUpdate.qml
services/Updates.qml
<!-- keep-deleted:end -->

ci-lint enforces the list: a path here that exists again fails the gate,
so resurrecting one on purpose means removing its line in the same commit.
`.github/workflows` covers all Actions — the gates run locally only.

## Compositor facade stays monolithic

Upstream v0.8.0 split `services/Compositor.qml` into a facade over
per-backend adapters (`CompositorHyprland.qml`, `CompositorNiri.qml`).
The fork's Compositor carries substantial fork-only work (windowGapX /
barSideGap, live title sync, occupancy counting) inside the monolith, so
the split was declined at the v0.8.0 merge rather than ported mid-
conflict. Standing resolutions: `services/Compositor.qml` merges as ours;
re-delete the two adapter files and their `services/qmldir` lines; the
ci-lint sections that referenced the adapters (niri event stream, inert
events, the Quickshell.Hyprland import allowlist) point at Compositor.qml
— and HyprDispatch.qml stays on that allowlist. Upstream's
adapter-contract lint section stays deleted. Adopting the split later is
a cold, deliberate port that retires this entry.

## Shared files — union, with contracts

- `config/GeneratedDefaults.qml`: take upstream's defaults wholesale, then
  re-append the fork's added keys. The settings contract (AGENTS.md) must
  hold after the merge, and key-set changes tie the merge to nixos-config
  per README.md's coupling rule.
- `services/ShellSettings.qml`: fork-added properties and `_schema` rows
  merge as a union with upstream's.
- `qmldir` files, `BarContent`'s widget registry, `barWidgetMeta`, and the
  zone-order defaults: unions — keep both sides' entries.

## What belongs here

An entry exists only where a merge could go wrong non-obviously: a
removal, a shared-file policy, or the feature-collision default above.
Fork-only features never get entries — new files don't conflict, and their
hooks into shared files are already covered by the union entries. A commit
that creates, changes, or moots a divergence updates this file in the same
commit; there are no batch cleanups.
