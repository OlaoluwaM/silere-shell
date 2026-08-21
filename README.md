# About this fork

This file says what the fork is for and the rules it runs under. How the
shell itself works (install, configuration, IPC, troubleshooting) is
[upstream's README](https://github.com/s3rven/silere-shell#readme); we keep
no copy here, because a copy only drifts. The working rules for agents are
in [AGENTS.md](AGENTS.md). Each fact lives in exactly one of these files,
so they never fight in a merge.

## What this is

A personal fork of
[s3rven/silere-shell](https://github.com/s3rven/silere-shell), a
Quickshell/QML desktop shell. It serves as the only shell of a
NixOS/Hyprland profile. A companion repository, `nixos-config`, consumes
the fork as a flake input (a source dependency pinned by commit), packages
it, and writes its declared defaults into `config/GeneratedDefaults.qml`
at build time. On top of upstream, the fork carries its own features (a
keybindings viewer, a redesigned media surface, a screen-recording
indicator, a wallpaper picker, a sound settings section, and the packaging
hooks that let Nix drive them) while keeping upstream's token architecture
and restraint intact.

## The three branches

- **`custom-branch`** is the branch of record. It is what `nixos-config`
  pins and where every feature lands, and its history is never rewritten.
  No rebase, no force-push, ever.
- **`upstream/main`** is upstream's development branch. We read it. We
  never write to it.
- **`main`** (this fork's, on origin) is a clean mirror of
  `upstream/main`, fast-forwarded now and then (GitHub's "Sync fork"
  button is enough). It exists so `git diff main...custom-branch` always
  shows the fork's true divergence. It never merges with `custom-branch`;
  the two branches do different jobs and stay apart on purpose.

## Merges, not rebases

We take upstream by merge, and only at upstream's release tags. Never from
the tip of `upstream/main`, so unreleased work stays out until it ships.
Each sync is one aggregate conflict pass that ends in one honest merge
commit (`c7d1cbd` was v0.6.1, `e3bf109` was v0.7.0). Why merge and not
rebase:

- Another repository pins `custom-branch` by commit hash. Rewriting
  history would orphan every lockfile that points at it.
- Undo stays simple. A bad merge still at the tip gets dropped with a
  reset. Once commits have stacked on top of it, revert it instead with
  `git revert -m 1 <merge>`. If you later re-merge a release you reverted,
  you must revert the revert first, or git treats those changes as already
  present.
- In conflicts, the fork's extensions win. Upstream's fixes come in where
  they don't fight a fork redesign.

After every merge, the same gates as any feature apply. They live in
[AGENTS.md](AGENTS.md).

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
or `wallpaperCommand`, or an upstream merge that changes the set), nothing
works until `nixos-config`'s silere module renders the same set into
`GeneratedDefaults.qml`. So the fork push, the silere-module change, and
the re-lock have to reach the machine in the same rebuild. Never
piecemeal.
