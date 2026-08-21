# About this fork

This file documents the fork itself — what it is for and the policy it
runs under. The shell's own documentation (install, configuration, IPC,
troubleshooting) is
[upstream's README](https://github.com/s3rven/silere-shell#readme); we
keep no copy here, because a copy only drifts. The working rules for
agents are in [AGENTS.md](AGENTS.md); fork policy lives here so the files
never fight in a merge.

## What this is

A personal fork of [s3rven/silere-shell](https://github.com/s3rven/silere-shell),
a Quickshell/QML desktop shell, serving as the sole shell of a NixOS/Hyprland
profile. The companion `nixos-config` repository consumes this fork as a
flake input, packages it, and renders its declared defaults (see
`config/GeneratedDefaults.qml`) at build time. On top of upstream, the fork
carries its own features — a keybindings viewer, a redesigned media surface,
a screen-recording indicator, a wallpaper picker, a sound settings section,
and the packaging hooks that let Nix drive them — while keeping upstream's
token architecture and restraint intact.

## Branches: custom-branch, upstream/main, origin/main

- **`custom-branch`** is the branch of record. It is what `nixos-config`
  pins, what every feature lands on, and it is never rewritten — no rebase,
  no force-push, ever.
- **`upstream/main`** is upstream's development branch. We read it; we never
  write to it.
- **`origin/main`** (this fork's `main`) is a clean mirror of
  `upstream/main`, fast-forwarded occasionally (GitHub's "Sync fork" button
  is enough). It exists so `git diff main...custom-branch` always measures
  the fork's true divergence. It is never merged with `custom-branch` and
  never needs reconciling — the two branches serve different jobs and stay
  apart by design.

## Merges, not rebases

Upstream is taken by **merge**, at upstream's **release tags** only — never
from the tip of `upstream/main`, so unreleased work stays out until it
ships. Each sync is one aggregate conflict pass ending in one honest merge
commit (see `c7d1cbd` for v0.6.1, `e3bf109` for v0.7.0). The reasons this is
merge-shaped and not rebase-shaped:

- `custom-branch` is pinned by another repository; rewriting its history
  would orphan every lockfile that references it.
- The undo story stays simple: a bad merge at the tip is dropped by reset
  before anything stacks on it; once commits have landed on top, it is
  reverted with `git revert -m 1 <merge>` instead (and a revert-of-revert is
  required before any later re-merge of the same release).
- In conflicts, this fork's extensions win; upstream's fixes are adopted
  where they don't fight a fork redesign.

After every merge, the same gates as any feature apply — they live in
[AGENTS.md](AGENTS.md).

## Pinning from nixos-config

`nixos-config` pins this fork by revision in its `flake.lock`. The re-lock
ritual, in order:

1. Push `custom-branch`.
2. In `nixos-config`: `nix flake update silere-shell` — confirm the new
   `rev` in `flake.lock` matches the fork tip just pushed.
3. Sanity-eval without building:
   `nix build .#nixosConfigurations.boreas.config.system.build.toplevel --dry-run`
4. Commit the lock alone as `chore: Re-lock silere-shell for <what changed>`.
5. `nixos-rebuild switch`, then live-test.

One coupling rule makes step ordering matter: a fork commit that adds or
removes a settings key — a packaging-only key (the `recordingStopCommand` /
`wallpaperCommand` pattern) or an upstream merge that changes the set — is
only satisfied once `nixos-config`'s silere module renders the same set
into `GeneratedDefaults.qml`. The fork push, the silere-module change, and
the re-lock must reach the machine in the same rebuild, never piecemeal.
