# Cava removal plan

Status: implemented and validated on September 10, 2026, against base
`f0b7c7928702d942cda94cf162e659bb24a12286`. The user approved committing the
complete removal after a final consistency check.
See [validation results](../.debug/cava-removal-20260910/RESULTS.md).

## Outcome and scope

Remove the Cava audio visualizer completely: its rendering component, bar
placements, service lifecycle, runtime profiles, settings, and tool reporting.
Keep ordinary media playback controls, metadata/artwork, track progress,
`mediaWidgetHelper`, the media popup, and normal bar layout.

This includes the Cava-dependent underline glow and fullscreen-watch demand.
Notification silencing, integrated OSD fullscreen handling, and other underline
sources remain supported. Retain Hyprland and Niri implementations.

Use deletion and simplification of existing code. Do not replace Cava with a
new renderer, add a dependency, or redesign the media widget. Do not restart
the production shell, push, deploy, or edit live user settings.

## Delegation

The approved roles ran with fresh, constructed context containing this contract,
owned paths, local instructions, and the fixed base revision. The models and
tiers below record the actual dispatch configuration.

| Role | Model and tier used | Responsibility and reason |
| --- | --- | --- |
| Orchestrator, me | Current lead agent | Own architecture, scope decisions, integration, validation, and final acceptance |
| Service IC | `gpt-5.6-terra`, standard, medium reasoning | Remove service/settings dependencies across a bounded set of related files |
| UI IC | `gpt-5.6-terra`, standard, medium reasoning | Remove QML consumers while preserving existing layout and media interactions |
| Reviewer | `gpt-5.6-sol`, standard, high reasoning | Review the integrated diff against the fixed removal contract and QML checklist |

The two implementation ICs can work in parallel because their file ownership
does not overlap. The reviewer starts after integration, with the contract and
diff but without the implementers' verdicts. A separate tooling IC is unnecessary
for this scope; I will handle that work during integration.

Each IC returns `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`, plus
changed files, checks actually run, and unresolved concerns. No subagent commits,
changes files outside its ownership, or dispatches another agent. A newly found
consumer outside those paths returns to me for assignment.

## Ownership

**Service IC** owns these files under `services/`:

- `Media.qml`: remove spectrum samples, visualizer client accounting, profile
  selection/writing/sweeping, reload signaling, process supervision, output
  parsing, and visualizer-only fullscreen timers/connections. Remove imports
  only when their remaining uses are gone; preserve MPRIS behavior and artwork.
- `ShellSettings.qml`: remove `mediaProgress`, `mediaVisualizerPreset`,
  `mediaVisualizerStyle`, `mediaVisualizerPosition`, their schema entries, and
  `centerVizConfigured`.
- `SystemTools.qml`: remove Cava availability and tool probing.
- `Notifications.qml`: remove only the visualizer's fullscreen-watch demand.
- `MenuState.qml`: remove the visualizer claim from the media settings description.

**UI IC** owns these paths:

- `modules/bar/widgets/MediaVisualizer.qml` and its `qmldir` entry: remove both.
- `modules/bar/widgets/MediaWidget.qml`: remove the visualizer loader and its
  state/hold timers; simplify progress-helper visibility without removing the
  helper or its media controls.
- `modules/bar/BarContent.qml`: remove center visualizer geometry and loader;
  preserve center widgets, title space, OSD handling, and compact behavior.
- `modules/bar/BarUnderline.qml`: remove Cava-dependent glow and simplify its
  combination with the remaining glow sources.
- `modules/menu/settings/SettingsMediaSection.qml`: remove visualizer controls
  and leave the other media options with coherent card/section structure.
- `modules/menu/settings/SettingsUnderlineSection.qml`: remove the visualizer
  from reactive-source availability.
- `modules/menu/settings/SettingsMaintenanceSection.qml`: remove Cava reporting.

**I own integration**, including `scripts/check.sh`, `install.sh`, `uninstall.sh`,
`bench.sh`, `probe-logic.qml`, relevant settings-migration probes/runners,
`config/Metrics.qml` comments, `TODO.md`, and `docs/upstream-divergences.md`.
Remove obsolete Cava checks, profile tests, benchmark output, dependency notices,
and the legacy uninstall prompt. Preserve historical reports and benchmark logs.
`Metrics.centeredSpanX()` still positions center widgets; do not remove it just
because the visualizer also used it.

## Sequence and verification

1. **Baseline and contract, lead.** Confirm the worktree and consumer inventory;
   record existing check results and media/bar behavior in a disposable instance.
   Verify the four removed settings against `GeneratedDefaults.qml` and
   nixos-config's `modules/home-manager/hyprland/modules/silere.nix`.
   Current inspection finds none of the four in either renderer, so no Nix
   configuration edit is expected. Verify the existing 52-property contract.

2. **Parallel implementation, two ICs.** Remove the owned producers and consumers.
   Each runs applicable static checks and reports remaining references. Full
   runtime checks wait for integration because either partial removal can leave
   the other half temporarily unresolved. Do not add temporary production stubs.

3. **Integration and compatibility, lead.** Inspect both diffs, finish tooling
   cleanup, and search every removed symbol for surviving consumers. Extend
   existing settings tests with files containing the old four keys. Current
   schema-based loading should ignore them, and a normal current-version save
   should omit them. Preserve the existing future-version unknown-key retention
   policy. Prove these behaviors before deciding whether any migration is needed;
   do not bump the settings version or add a migration solely for deletion.

4. **Review, reviewer then lead.** Check spec compliance first, then correctness
   and quality using `code-review`, `consistency-check`, and the repository-local
   `qt-qml-review`. Complete all six QML missions; record actual coverage and
   attributable lint output. The reviewer stays read-only. I verify findings,
   assign fixes to their owners, and check the integrated result.

5. **Acceptance, lead.** Run the gates below, resolve failures, update
   the divergence ledger to keep the visualizer removed on future imports, and
   close the TODO only after acceptance. After the final consistency check,
   commit the complete removal, tests, and documentation together. Keep the
   service and UI deletions in the same commit.
   No nixos-config change was needed; the 52-property contract is unchanged.

## Acceptance gates

- Search active `services/`, `modules/`, `config/`, scripts, and build inputs for
  all removed settings, Cava process/profile symbols, and visualizer types.
  No executable consumer, registration, or tool requirement remains. Retired-key
  compatibility fixtures and historical documentation are intentional references.
- Run `bash scripts/ci-lint.sh`, then
  `nix develop . --command bash scripts/check.sh`. Require zero failures, inspect
  changed warnings and settings/state counts, and keep the defaults contract
  intact. Removing the optional Cava warning is expected.
- In a disposable Hyprland instance, verify media absent, playing, paused, and
  stopped; track progress and popup controls; center widgets/title; compact mode;
  reduced motion; idle/fullscreen transitions; and unrelated underline sources.
  Use an available MPRIS player for live controls and label synthetic coverage.
- Verify no Cava child process or new shell-owned Cava profile appears during
  those scenarios, and no visualizer settings or maintenance warning remains.
- Compare short `bench.sh` samples under matching idle and playback conditions.
  Treat them as regression checks, not proof of a specific performance gain.
  Retain Niri static/mock checks; do not claim live Niri verification.
- Verify the final working diff contains the entire removal and no unrelated
  edits. Do not modify live user files or delete legacy Cava files on this machine
  as part of source cleanup.

## Estimate and risks

Budget roughly 2–4 hours including integration, review, and live checks. Most
implementation is deletion; saved-settings compatibility and interaction tests
are the main sources of uncertainty. Delegation splits implementation effort,
but integration and review remain sequential. Missing live playback or an
unexpected Nix/settings coupling can extend the estimate.

The main risks are confusing `mediaProgress` (the visualizer toggle) with actual
track progress, removing shared fullscreen or geometry helpers, and overlooking
the notifications/underline consumers. The ownership map and acceptance checks
above explicitly cover those boundaries.
