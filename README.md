# Silere-shell Fork

[demo](./assets/demo.mp4)
[demo2](./assets/demo2.mp4)

## What this is

A personal fork of [s3rven/silere-shell](https://github.com/s3rven/silere-shell), a Quickshell/QML desktop shell. It serves as the only shell of a NixOS/Hyprland profile.

Upstream v0.9.0 requires Quickshell 0.3.1 or newer. This repository's
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
  they don't fight a fork redesign. The standing resolutions — what stays
  deleted, which files merge as unions, what happens when upstream ships a
  feature the fork already has — live in the
  [divergence ledger](docs/upstream-divergences.md). Resolve by the ledger,
  then walk it and retire what the merge made moot, inside the merge
  commit. A conflict no entry anticipates and that needs a real decision
  pauses the merge until it's settled cold.

Before any merge work, the maintainer creates and publishes an annotated
safety tag on the current `custom-branch` tip. Its name is
`pre-upstream-<release-tag>`; for example, the v0.9.0 merge anchor is created
with `git tag -a pre-upstream-v0.9.0 a4ecf7e -m "before upstream v0.9.0"`.
The merge does not start until that tag exists on the remote. It makes the
pre-merge tip easy to recover without changing the rule above: reset only
while the merge is still at the tip, and revert once later commits exist.

Once the merge, its resolution record, all merge-specific follow-up commits,
and the repository gates are complete, the maintainer creates and publishes a
second annotated tag on that final validated HEAD. Its name is
`post-upstream-<release-tag>`. The pre-merge and post-merge tags bracket the
complete integration. Create the post-merge tag before unrelated work resumes,
and never move either tag.

Before the first conflict pass, enable rerere once per clone
(`git config rerere.enabled true`): an aborted or repeated attempt then
replays the hunks already resolved instead of presenting them again.

After every merge, the same gates as any feature apply. They live in
[AGENTS.md](AGENTS.md).

The v0.9.0 merge commit omitted its usual conflict narrative. Its
[resolution record](docs/upstream-merge-v0.9.0.md) preserves those decisions
without rewriting published branch history.

On 2026-09-04, the maintainer explicitly authorized a one-off selection of
unreleased commits. The [selective integration record](docs/upstream-picks-2026-09-04.md)
records their provenance and exclusions. This exception does not change the
release-tag policy above or authorize further development-branch imports.

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
