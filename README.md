# Silere-shell Fork

[demo](./assets/demo.mp4)
[demo2](./assets/demo2.mp4)

## What this is

A personal fork of [s3rven/silere-shell](https://github.com/s3rven/silere-shell), a Quickshell/QML desktop shell. It serves as the only shell of a NixOS/Hyprland profile.

Upstream v1.0.0 requires Quickshell 0.3.1 or newer. This repository's
development flake pins that release; the deploying NixOS configuration must
supply the same minimum before it re-locks the fork.

It is the shell for the Hyprland profile in my [`nixos-config`](https://github.com/s3rven/silere-shell). `nixos-config` consumes
the fork as a flake input (a source dependency pinned by commit), packages it, and writes its declared defaults into `config/GeneratedDefaults.qml` at build time.

On top of upstream, the fork carries its own features:

- a keybindings viewer
- a redesigned media surface
- a screen-recording indicator
- a wallpaper picker
- a sound settings section
- packaging hooks that allow for some declarative configuration

All this while keeping upstream's token architecture and restraint intact.

## There are a couple important branches

- **`custom-branch`** is where all our custom work lies. It is what `nixos-config`
  pins and where every feature lands. Agents never rewrite its history;
  selected upstream changes land as new commits.
- **`custom-branch-testing`** for experimental stuff
- **`upstream/main`** is upstream's development branch. We read it to select
  useful changes. We never write to it.
- **`main`** (this fork's, on origin) is a clean mirror of `upstream/main`.
  Compare its tree with the fork using `git diff main custom-branch`.
  Selective imports do not advance the shared ancestor, so a three-dot diff
  does not compare the current upstream and fork trees. `main` never merges
  with `custom-branch`; the two branches do different jobs.

## Selective upstream integration

Select useful upstream changes individually. Releases are review checkpoints,
with no obligation to import the release. Prioritize applicable bug fixes,
then improvements the fork actually needs. Selected commits may come from a
release or development history; inspect exact commits and their dependencies
before importing either. The rationale is in
[ADR 0003](adrs/0003-integrate-upstream-changes-selectively.md).

For each integration:

1. Inspect the upstream change against the current fork. Identify its benefit,
   prerequisites, affected fork behavior, and validation before editing. Use
   the [divergence ledger](docs/upstream-divergences.md) to resolve collisions;
   a design decision outside its standing rules needs maintainer judgment.
2. Keep the scope to one coherent change and its necessary dependencies.
   Cherry-pick compatible implementations; port the relevant behavior into
   redesigned areas. A clean application is not proof of compatibility.
   If dependencies materially expand the agreed scope, reassess with the
   maintainer before importing them.
3. Record the upstream repository and full source SHA(s) in the commit message.
   Use `git cherry-pick -x` for direct picks and verify the provenance survives
   conflict resolution. Adapted commits name their sources and explain the
   material adaptations. Keep one commit per task item, per AGENTS.md.
4. Review the affected ledger entries and update or retire them in the commit
   that changes the divergence. Run the repository gates in
   [AGENTS.md](AGENTS.md), plus checks of the affected fork behavior. Validate
   interactive Hyprland changes in a throwaway instance and label mock or
   static coverage accurately.

Periodically review upstream changes since the last review, including fixes
in areas we previously adapted. Record the reviewed upstream SHA and selected,
deferred, or rejected change groups with brief reasons in a dated integration
record under `docs/`. Reviewing a release does not mark it as imported.

History stays intact because nixos-config pins this branch by commit. Undo a
landed selective import with a revert, accounting for any dependent follow-ups.
Selective integration does not authorize rebases, amendments, or resets of
`custom-branch` history.

### Exceptional full merges

Full release merges require a separate, explicit maintainer decision after
reassessing their benefit, scope, and reconciliation cost. Approval for a
selective import does not authorize a full merge. If approved, target an exact
upstream release commit and reconcile earlier picks and adaptations using
their provenance and the ledger.

The maintainer creates and publishes an immutable annotated
`pre-upstream-<release-tag>` before merge work starts, then an immutable
`post-upstream-<release-tag>` after the merge, resolution record, follow-ups,
and gates are complete, before unrelated work resumes. These tags bracket
the complete integration. Agents never create or publish them. Enable
`rerere` per clone (`git config rerere.enabled true`) before resolving
conflicts. Walk the full ledger during resolution and validation.

Undo a landed merge with `git revert -m 1 <merge>`, accounting for separate
follow-up commits. Re-merging a reverted release requires addressing the
revert first; the original merge remains in history.

### Historical integrations

The [v0.9.0 resolution record](docs/upstream-merge-v0.9.0.md),
[September 4 selective integration record](docs/upstream-picks-2026-09-04.md),
and [v1.0.0 resolution record](docs/upstream-merge-v1.0.0.md) describe work
under the previous release-tag policy. Their historical approvals do not
authorize new imports. Upstream's `v1.0.0` and the older fork tag with that
name identify different commits; the v1.0.0 record gives the exact source.

## Pinning from nixos-config

`nixos-config` pins this fork by commit in its `flake.lock`. Re-locking
goes in this order:

1. Push `custom-branch`.
2. In `nixos-config`, run `nix flake update silere-shell`. Check that the
   new `rev` in `flake.lock` matches the tip you just pushed.
3. Sanity-check the evaluation without building:
   `nix build .#nixosConfigurations.boreas.config.system.build.toplevel --dry-run`
4. Commit the lockfile alone, as
   `chore: Re-lock silere-shell for <what changed>`.
5. `nixos-rebuild switch`, then test it live.

One coupling rule makes the order matter. When a fork commit adds or
removes a settings key (a packaging-only key like `recordingStopCommand`
or `wallpaperCommand`, or an upstream import that changes the set), nothing
works until `nixos-config`'s silere module renders the same set into
`GeneratedDefaults.qml`. So the fork push, the silere-module change, and
the re-lock have to reach the machine in the same rebuild. Never
piecemeal.
