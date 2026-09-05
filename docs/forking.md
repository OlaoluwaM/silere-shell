# Forking Silere

Fork it, strip it, rebrand it. Most changes touch two or three files, and
`bash scripts/check.sh` tells you if you missed one — you don't need to know the
whole shell to change part of it.

## Where things are

- `config/` — colours, durations, sizes
- `services/` — settings and system state, no UI
- `modules/` — one folder per surface: `bar/`, `menu/`, `notifications/`, `osd/`, …
- `scripts/` — install, uninstall, checks, and development probes

## Changing things

**Colours.** All of them live in `config/Theme.qml`. Change a token, the whole shell
follows. Don't paste a hex into a widget.

**A new setting** goes in four places:

1. a property in `services/ShellSettings.qml` — its value there is the default
2. an entry in that file's `_schema`, carrying a `sec:` that names a settings page
3. wherever you read it
4. a row on that same page under `modules/menu/settings/`

Saving is automatic. Put the row on the page the `sec:` names — that is what dots the
category once the value leaves its default, so a mismatch marks a page the setting
isn't on.

**A new component** must be listed in its folder's `qmldir`. Forget it and it fails
only when running, as `X is not a type` — that one confuses everybody once.

**A new bar widget** is the longest chain in the shell, six places:

1. `modules/bar/widgets/MyThing.qml` — start from `Volume.qml`, it is the smallest
   complete one. A widget is a `Pill` exposing `show`, and `BarZone` reads that.
2. its line in `modules/bar/widgets/qmldir`
3. a `Component` in `modules/bar/BarContent.qml`, added to `_widgetComponents` under
   the key you want
4. an entry in `barWidgetMeta` in `services/ShellSettings.qml` — glyph, label, group,
   and the `setting` name that hides it (empty string means it cannot be hidden)
5. that `setting` as a property plus a `_schema` entry whose `sec:` names the
   `widgets` page, if it is hideable
6. the key appended to one of the `barWidgetOrder*` defaults, or it ships in no zone
   and only appears once someone drags it out of the arranger

If it needs a backend that may be absent, gate it in `BarZone._widgetEnabled()` next to
the `battery` and `brightness` cases; returning false there hides the widget rather than
drawing a dead one.

**Less shell.** Surfaces don't import each other, so you can delete a `modules/`
folder along with its `import` and loader in `shell.qml` and the rest keeps working.

## Renaming your fork

The name appears a few hundred times, nearly all of it cosmetic. Three matter:

- the **layer-shell namespaces** (`silere-bar`, `silere-menu`, …) — compositor blur
  and animation rules match those strings
- the **config directory** `"/silere-shell"` in `services/ConfigStore.qml` —
  changing it leaves the old `settings.json` behind

`grep -rIl silere .` finds the rest.

## Before you push

`bash scripts/check.sh` runs the type check, the probes and the structural rules, and
names anything it doesn't like. Two of those rules catch people out early: use
`MotionBehavior` rather than a bare `Behavior` (it carries the reduce-motion gate),
and size rows with `Metrics.rowHeightFor()` rather than a number.

## Developing with Nix

This fork ships a development-only `flake.nix`: `nix develop` gives you `qs`,
the matching Qt QML validation tools, JetBrainsMono Nerd Font, `hyprctl`,
`matugen`, and the other tools the shell and its checks need. Run the gates
there with `nix develop . --command bash scripts/check.sh`; the development
shell makes missing QML tools or the shipped font fail, so type and layout
checks have real coverage. A normal installed-shell diagnostic remains
best-effort and reports those unavailable prerequisites as skipped.

The flake exposes no packages on purpose: the NixOS configuration that deploys
this fork consumes the repo as a plain source input and does its own packaging
(it substitutes `config/GeneratedDefaults.qml` at build time), so packaging
logic lives there, not here.
