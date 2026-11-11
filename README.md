# Silere-shell Fork

[demo](./assets/demo.mp4)
[demo2](./assets/demo2.mp4)

## What this is

A personal Quickshell/QML desktop shell, begun as a fork of [s3rven/silere-shell](https://github.com/s3rven/silere-shell) and now developed in its own direction. It serves as the only shell of a NixOS/Hyprland profile.

The shell requires Quickshell 0.3.1 or newer, the floor that
`SILERE_MIN_QUICKSHELL` in `scripts/lib/qml-modules.sh` sets. This repository's
development flake pins a later commit, which follows Hyprland's workspace id
changes and emits `WlSessionLock.locked` on unlock, the signal the lock exits
on; the deploying NixOS configuration must supply a Quickshell at least that
new before it re-locks the fork.

It is the shell for the Hyprland profile in my [`nixos-config`](https://github.com/OlaoluwaM/nixos-config). `nixos-config` consumes
the fork as a flake input (a source dependency pinned by commit), packages it, and writes its declared defaults into `config/GeneratedDefaults.qml` at build time.

On top of upstream, the fork carries its own features:

- a keybindings viewer
- a redesigned media surface
- a screen-recording indicator
- a wallpaper picker
- adaptive frosted glass that follows a sample of the wallpaper
- a sound settings section
- a lock screen, `lock.qml`: its own short-lived process beside `shell.qml`,
  started for each lock by nixos-config's `silere-lock` wrapper, with hyprlock
  as the fallback
- packaging hooks that allow for some declarative configuration

All this while keeping upstream's token architecture and restraint intact.

## There are a couple important branches

- **`custom-branch`** is where all our custom work lies. It is what `nixos-config`
  pins and where every feature lands. Agents never rewrite its history;
  selected upstream changes land as new commits.
- **`upstream/main`** is upstream's development branch. We read it to select
  useful changes. We never write to it.
- **`main`** (this fork's, on origin) is a clean mirror of `upstream/main`.
  Compare its tree with the fork using `git diff main custom-branch`.
  Selective imports do not advance the shared ancestor, so a three-dot diff
  does not compare the current upstream and fork trees. `main` never merges
  with `custom-branch`; the two branches do different jobs.

## Cherry-picks from upstream

There is no reconciliation with upstream, at any point, and no full merge.
An upstream idea or commit comes in only as an individual cherry-pick the
maintainer chooses, adapted to this code. Prioritize applicable bug fixes,
then improvements the fork actually needs. Selected commits may come from a
release or development history; inspect exact commits and their dependencies
before importing either. The rationale is in
[ADR 0006](adrs/0006-stop-reconciling-with-upstream-and-take-only-chosen-cherry-picks.md).

For each integration:

1. Inspect the upstream change against the current fork. Identify its benefit,
   prerequisites, affected fork behavior, and validation before editing.
2. Keep the scope to one coherent change and its necessary dependencies.
   Cherry-pick compatible implementations; port the relevant behavior into
   redesigned areas. A clean application is not proof of compatibility.
   If dependencies materially expand the agreed scope, reassess with the
   maintainer before importing them.
3. Record the upstream repository and full source SHA(s) in the commit message.
   Use `git cherry-pick -x` for direct picks and verify the provenance survives
   conflict resolution. Adapted commits name their sources and explain the
   material adaptations. Keep one commit per task item, per AGENTS.md.
4. Run the repository gates in [AGENTS.md](AGENTS.md), plus checks of the
   affected fork behavior. Validate interactive Hyprland changes in a
   throwaway instance and label mock or static coverage accurately.

When upstream is reviewed for picks, record the reviewed upstream SHA and
selected, deferred, or rejected change groups with brief reasons in a dated
integration record under `docs/`.

The [docs index](docs/README.md#integration-records) summarises each dated
integration record.

History stays intact because nixos-config pins this branch by commit. Undo a
landed cherry-pick with a revert, accounting for any dependent follow-ups.
A cherry-pick does not authorize rebases, amendments, or resets of
`custom-branch` history.

### Historical integrations

The [docs index](docs/README.md#historical-integrations) summarises the
records made under the previous release-tag policy.

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
works until `nixos-config`'s silere module
(`modules/home-manager/hyprland/modules/silere.nix`) renders the same set into
`GeneratedDefaults.qml`. So the fork push, the silere-module change, and
the re-lock have to reach the machine in the same rebuild. Never
piecemeal.

## Other documents

- [docs/debugging.md](docs/debugging.md): finding the shell's logs in the
  journal, and debugging the lock, notifications, network, caffeine and
  night light.
- [TODO.md](TODO.md): deferred work, each entry with why it waited.
- [scripts/README.md](scripts/README.md): what the checks and probes cover.
- [docs/README.md](docs/README.md): an index of the documents under `docs/`,
  the integration records and the decision records.
