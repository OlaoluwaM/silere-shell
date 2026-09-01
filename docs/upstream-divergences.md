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
iterates it, and each release merge deletes it again). The stack's
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

- Notifications keep the fork's `ExpandableBody` interaction and the popup
  layer's constant screen-sized height. Take upstream delivery features such
  as grouping, inline replies, batch retirement, and sender-image hardening
  around those two constraints.
- The Bluetooth bar widget stays an actionable `StatusActionPill` that opens
  the configured manager. Take compatible upstream service, accessibility,
  hint, and lifecycle improvements without replacing it with a passive pill.
- Power profiles keep the command backend and its `asusctl` fallback. Take
  backend-neutral upstream fixes, but do not replace this with a UPower-only
  implementation because the deploying machine runs `asusd`.
- The fork's media card lives at `modules/menu/controls/MediaCard.qml` and its
  redesign wins. Never restore the obsolete `modules/menu/MediaCard.qml` path;
  port compatible upstream privacy and metadata fixes into the controls file.

## What belongs here

An entry exists only where a merge could go wrong non-obviously: a
removal, a shared-file policy, or the feature-collision default above.
Fork-only features never get entries — new files don't conflict, and their
hooks into shared files are already covered by the union entries. A commit
that creates, changes, or moots a divergence updates this file in the same
commit; there are no batch cleanups.
