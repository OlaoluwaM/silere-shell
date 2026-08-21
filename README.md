# Silere-shell Fork

## What this is

A personal fork of [s3rven/silere-shell](https://github.com/s3rven/silere-shell), a Quickshell/QML desktop shell. It serves as the only shell of a NixOS/Hyprland profile.

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
  pins and where every feature lands. It's history can only be rewritten manually. Syncs with upstream/main can only be reconciled through merges, never rebases
- **`custom-branch-testing`** for experimental stuff
- **`upstream/main`** is upstream's development branch. We read it. We sometimes sync with it. We never write to it.
- **`main`** (this fork's, on origin) is a clean mirror of `upstream/main`. It exists so `git diff main...custom-branch` always
  shows the fork's true divergence. It never merges with `custom-branch`; the two branches do different jobs and stay apart on purpose.

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
  present. Or we can drop the commit entirely
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
