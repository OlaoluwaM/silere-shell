# Cava removal validation

Date: September 10, 2026. Base: `f0b7c7928702d942cda94cf162e659bb24a12286`.
Status: implemented and validated; final consistency check completed and commit
authorized by the user.

## Changes

Removed the visualizer component and registrations, bar placements, underline
source, Cava process/profile management, four runtime settings, availability
reporting, and obsolete script checks. Preserved media controls, metadata,
artwork, track progress, the media helper, and shared fullscreen behavior.
Updated the upstream divergence ledger. The Nix defaults contract remains
52/52/52; the removed runtime settings were absent from both defaults renderers.

The existing migration runner now covers retired keys in current and future
settings versions. Loading leaves files unchanged. Normal current-version saves
omit retired keys; future-version saves retain unknown keys and their version.
No settings version bump or migration was required.

## Gates and review

- `bash scripts/ci-lint.sh`: passed. The tracked-file registration loop now skips
  deleted worktree files, so removal can be checked before staging.
- `nix develop . --command bash scripts/check.sh`: passed with five environmental
  warnings. The removed optional Cava warning accounts for the decrease from six.
- 197 QML files checked; 405 logic checks, 15 bump checks, 164 overlay coordinator
  checks, and 7 Bluetooth details checks passed. All settings migration cases
  passed, including the two added retired-key cases.
- Default-off smoke loaded 36 settings; live mutation covered 165 states across
  55 surfaces. Layout fit and reduced-motion surface variants passed.
- Independent contract, consistency, and six-mission QML review found no remaining
  defects attributable to the change. Initial missing Quickshell imports were
  restored, and the issue template's stale visualizer category was removed before
  final acceptance.
- Deterministic QML review lint emitted existing diagnostics with no reportable
  changed-line findings. System lint of the migration probe passed without
  diagnostics. In the runner's module context, the logic probe had 155 existing
  dynamic QObject inference warnings, zero errors, and zero import diagnostics.

The service and UI ICs each ran `gpt-5.6-terra`, standard tier, medium reasoning.
The independent reviewer ran `gpt-5.6-sol`, standard tier, high reasoning.
The lead integrated the changes, owned tooling and validation, and accepted the
final result. Review missions ran within the reviewer, without further agents.

## Runtime coverage

The retained JSON files record 28 before/after checks and 22 additional transition
checks, all passing. Disposable shell instances used private configuration and a
private session bus on the real Hyprland desktop. A synthetic player exported a
real MPRIS D-Bus interface; no actual audio or personal player was controlled.

Checks covered absent/playing/paused/stopped/removed players, next/previous,
seeking and track position, popup opening/closing, compact and reduced-motion
settings, retired settings, and notification/OSD fullscreen-watch demand.
A disposable window entered and exited real Hyprland fullscreen: playback
continued and notification silencing followed the fullscreen state.

Idle was simulated through a test-only property in a disposable copy of Idle.qml.
It closed the media popup, blocked re-entry, and settled media animation while
playback continued; leaving idle restored animation eligibility. This establishes
the shell's response to idle state, not the compositor's inactivity timer.
Initial probe failures were corrected for window focus, the host's Lua dispatch
syntax, and temporary-project import/copy context; no production workaround was
added. Runtime logs contain no matching QML load, binding, or assignment errors.
No new shell-owned Cava profile appeared. Active source has no Cava process path.

Niri coverage remains static/mock, including the existing 14-check focus probe.
No live Niri session or subjective visual inspection is claimed. Surface/layout
probes and source review cover preserved center/title and underline paths.
The production shell was not restarted or deployed, and live user settings and
legacy Cava files were not modified.

## Short performance comparison

Five-second samples are regression checks only. The baseline had no running Cava
visualizer, so these samples cannot measure the savings from removing an active
visualizer. Startup work contributes to the idle samples.

| Sample | Before | After |
| --- | --- | --- |
| Idle main CPU | 1.2% | 1.4% |
| Idle process-tree CPU | 15.0% | 15.2% |
| Idle average RSS | 217 MB | 221 MB |
| Playing main/process-tree CPU | 1.4% | 1.4% |
| Playing average RSS | 218 MB | 219 MB |
| Playing threads | 18 | 17 |
| Playing helpers / FD change | 0 / 0 | 0 / 0 |

These short samples show no meaningful regression signal. They do not establish
long-run performance or a quantified performance improvement.
