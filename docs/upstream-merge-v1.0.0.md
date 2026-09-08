# Upstream v1.0.0 merge resolution record

This integration merges upstream release commit
`f17587c963664efad1b6a670d1340a32a9322ef1` into fork commit
`38c1d081175015059af77d5b832df0dcb05d1d4b`. The shared ancestor is
`78fb1eaf368b75e39bcac35be7fc599a70b87631`, upstream v0.9.0.

Upstream's annotated v1.0.0 tag object is
`2f591eea70bde633987b3d9207a9050418a643bf`. The repository already has an
older fork tag called `v1.0.0`; it is not the integration source and is
left untouched. The published annotated `pre-upstream-v1.0.0` tag protects
the fork fixed point above.

## Compatible changes

- Hyprland special-workspace windows remain candidates for tray, media,
  and notification source actions, and focus uses their workspace names.
- Configuration writes include waits for the directory in their pending
  state. Failed writes recheck the directory, setup failures retain their
  exit status, and directory retries are bounded.
- Temperature discovery rejects results from a canceled generation.
  Battery readings remain bounded while the backend scale settles, and a
  jump through both warning thresholds selects the critical warning.
- A timed-out Matugen repair cannot become successful on its later exit.
  OSD warning replay and compatible interrupted-motion fixes are retained.
- Bar compact measurements recover after widgets move between zones.
  Compatible layout, calendar, and notification accessibility changes fit
  around the fork's existing components.
- `mediaRemoteArt` defaults to false. The Media settings page can enable
  HTTPS artwork; HTTP remains rejected. Local and in-memory artwork remain
  available. `notifCriticalBypass` defaults to true and makes the existing
  critical-alert exception configurable without restoring scheduled DND.
- Settings use ordered migration steps while retaining fork backup and
  widget-order protections. The settings schema remains version 1.
- Benchmark reporting adds warm sampling, JSON output, and sample context.
  Probe shutdown has a forced termination fallback; layout probes detect
  text shrinking as well as clipping and truncation.

## Fork-preserving resolutions

- Audio, its IPC interface, the sound settings section, and the privacy
  widget retain their existing implementation. The PipeWire control
  extraction and duplicate microphone widget are excluded.
- The media card stays under `modules/menu/controls`. Its control layout
  and closed-host artwork guard remain; the obsolete upstream path stays
  absent.
- Palette transitions retain `MatugenTheme`, the leaf-fade gate, and the
  glass/control tokens. Upstream's second palette transition mechanism and
  unrelated slider, switch, and media-button restyling are excluded.
- Dynamic workspaces retain the fork's occupied-workspace list, trailing
  empty workspace, and marker behavior. Upstream's replacement workspace
  models and their extra setting are excluded.
- Bar tooltips retain the service, popup host, widget bindings, and toggle.
- Notifications retain `ExpandableBody`, the constant screen-sized popup
  layer, stable history-run expansion, and the corrected reload ordering
  and capacity handling. The duration picker remains the DND interface.
- Bluetooth remains actionable. Power profiles retain their command
  backend and asusctl fallback. Night light retains systemd ownership;
  additional lock/night-light providers and their settings are excluded.
- Settings retain reset/migration backups, backup hardening, locked-order
  scrubbing, future-version preservation, and fork defaults. Existing
  settings-group and marker defaults are retained.
- Release, self-update, package-update, and distribution paths remain
  absent. New maintenance launchers, updater tests, compatibility manifests,
  and upstream-only performance history are excluded with their consumers.
  Existing fork install/check/portability scripts retain their packaging
  boundaries; compatible checks are adapted separately.
- Shared registries and `qmldir` files retain every fork entry. No rejected
  component is registered. The two new runtime settings do not add generated
  Nix keys.

## Already covered before this merge

The September 4 selective integrations already supplied app-owned tray
icons, the WindowActions rename, artwork fallbacks, and notification
identity guards. Local follow-ups supplied popup anchoring, closed-host
artwork protection, and correct notification reload/capacity behavior.
Those corrections are reconciled rather than replaced by their older
upstream equivalents. See the [selective integration record](upstream-picks-2026-09-04.md).

## Validation

The resolved candidate passed `bash scripts/ci-lint.sh` and
`nix develop . --command bash scripts/check.sh`, each with exit 0. The full
check retained the same five environmental warnings as the pre-merge
baseline: optional cava and powerprofilesctl, the source-install autostart
check, and two source-install Matugen path checks. The fork retains its
packaged service, Matugen setup, and asusctl backend.

- QML bytecode and import checks passed for 197 files.
- Behavioral probes passed 383 checks. Notification reload and urgency
  policy passed 20 checks in each persistence mode; history grouping passed
  23; popup lifecycle passed 22 in each motion mode.
- The new private configuration fixture passed six QML assertions plus
  host checks of exact bytes and 0700/0600 directory/file modes. It forces
  blocked-directory startup and a real post-startup write failure, removes
  each blocker, and verifies automatic recovery.
- Niri focus passed 14 mock checks. No live Niri claim is made.
- Surface construction, 174 setting mutations across 55 surfaces, and
  label-fit checks across the supported type range passed. The smoke tests
  covered startup, 36 default-off settings, and six malformed settings files.
- All six QML review missions completed across the 39 changed QML files.
  Two history accessibility references were corrected to use the retained
  ExpandableBody API and shared pointer/accessibility activation logic.
  Final deterministic review retains 26 changed-line pattern diagnostics
  matching local conventions or intentional test/state operations. System
  qmllint retains 13 changed-line dynamic-object/signal-metadata warnings;
  the concrete runtime probes pass. Neither lint output is described as
  warning-free.
- The generated-default, ShellSettings reference, and Nix render key sets
  remain identical at 52 each. GeneratedDefaults is unchanged. The two new
  runtime settings require no coupled Nix option change.

Separate live checks used temporary instances. On Hyprland 0.56.2 with the
Lua dispatcher, a temporary window was moved to a named special workspace;
the merged backend resolved its negative ID and workspace name, opened the
workspace, and emitted the matching compositor focus event. The test window
and probe were then closed. Polling the later active window alone was
insufficient because focus changed again; the accepted check observes the
raw compositor event.

A private-bus shell opened the media, popup, and maintenance settings pages,
reopened Home idempotently, and completed a warm benchmark. JSON round-tripped
control bytes U+0001 through U+001F, quotes, backslashes, and a leading-zero
sample duration; widget and font metadata matched effective settings.
The live check caught and corrected Quickshell's `show` CLI subcommand
collision by separating IPC arguments with `--`, and a settings-constraint
parser that did not account for nested brackets. No QML runtime errors were
reported in those menu checks.

A separate offscreen probe populated the actual history page and passed seven
assertions for notification descriptions, body expansion through
`Accessible.pressAction`, and opening a folded three-row run. Replacing an
expanded history produced a height-binding warning at RecentPage.qml:359;
the same transition through the original pointer/body path reproduced that
warning with the pre-merge RecentPage. It remains a pre-existing follow-up,
not a clean-runtime claim for this scenario. No screen-reader client was
used.

Hardware battery transitions, temperature-discovery races, and idle/motion
interruptions use targeted probes rather than induced desktop conditions.
The merge does not activate the packaged shell. Publishing the branch,
creating the post-merge tag, updating the Nix input lock, and deployment
validation remain the maintainer's steps in README order.

## Review follow-ups

The migration follow-up blocks persistence when the legacy-file backup fails.
The same gate covers immediate migration, user edits, queued widget-order
scrubbing, and reload teardown. A later load can retry the unchanged source;
backup retries alternate trailing whitespace so FileView performs the write.
The isolated regression covers failed backups with unlocked and locked widget
orders, editing and reloading while blocked, recovery after repair, and
unchanged current/future-version files. An accepted external replacement
invalidates the previous save cache so equivalent migrated values still reach
disk. The write block protects the loaded legacy source; replacing or removing
that source follows the existing load policy.
