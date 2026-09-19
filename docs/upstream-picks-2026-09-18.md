# Selective upstream integration: calendar, fullscreen, and popup checks

Status: implemented, validated, and reviewed through the C2 correction,
with the test-coverage limit below. Base:
`f91731ae2cc415c267accb37a162f9d4d4258812`.

## Review range and selected scope

The review covers 22 upstream commits after
`0ffa657ffbfb7caefc04f59c0e6bf7a9eed0760a`, through
`d07d50981c7ec3348449120240fcd79961b11e2f` (v1.1.1 packaging).
Sources are from <https://github.com/s3rven/silere-shell>.

The maintainer approved the following six changes, with the lead retaining
integration and final judgment and implementation ICs reviewing their own work.

| Source commit | Selected behavior |
| --- | --- |
| `4464006a9980b15313a16e660a6faeef6ef924be` | Block calendar-mark writes until the initial read establishes whether writing is allowed. |
| `35e3c18e505c28e5ef48413a5e4da20c9eaf35dd` | Treat Hyprland fullscreen mode 2 as fullscreen, excluding maximized mode 1. |
| `4020a2397be63a177eb2afc4c54e026d457b4e75` | Animate notification stack movement after initial placement, reset placement when a hidden slot returns, and use upstream's 10 px card gap. |
| `30796cad909ffe2ddd3fb376b6bccfaebc3e8dbb` | Build layer-shell surfaces in an isolated probe with unmapped windows and a real Wayland backend. |
| `9c97505b6c4950e9f803073e6c8522db28f0e979` | Correct the inert Hyprland IPC event name to `minimized`. |
| `54f33eb77fa5d46c4fa19adf424e9306d1d3457a` | Document `barWidgetKeys` in the widget-registration steps. |

Adapt the selected behavior to the fork; omit upstream changelog/release files.
Keep settings keys, dynamic workspaces, notification expansion, popup window
height, and the shared popup animation contract. The panel probe must retain
the fork's existing sequential checks and isolate shell-owned configuration and
state. It must stop only the process it starts.

Hyprland's [fullscreen-state documentation](https://wiki.hypr.land/Configuring/Basics/Dispatchers/#fullscreenstate)
confirms the distinction between maximized mode 1 and fullscreen mode 2.

## Other reviewed groups

- Defer `fa70e8d` settings-dot filtering. It requires the previously deferred
  `4fb1c11` behavior and a separate adaptation to the fork's settings UI.
- Defer `03ce772` popup motion and geometry. The patch combines geometry fixes
  with scaling and timing changes that overlap the fork's shared animation.
- Skip `8be8c54`: the fork does not have upstream's RecentNav component.
- Skip `e846787`: the fork does not have the affected notification sweep.
- Reject `dbf4861` dynamic-workspace removal under the standing divergence.
- Leave `be3e6a6`, `97b2c8d`, and `342fa0d` cleanup/worktree-lint changes for
  separate consideration. They are outside this approved batch.
- Skip visualizer, installer, upstream README, changelog, release, and AUR
  changes: their affected features or distribution paths are absent here.

## Acceptance

1. Calendar: an early toggle cannot write over unread saved marks; a supported
   loaded file or missing file permits writes; corrupt, unreadable, and newer
   files remain protected. The guard does not promise to replay an early click.
2. Hyprland: mode 0 and mode 1 are not fullscreen; mode 2 is fullscreen. Preserve
   the compositor facade and Niri backend. The inert-event spelling change must
   not alter handling of unrelated events.
3. Notifications: first placement and reappearance settle immediately; later
   stack movement animates. Preserve timeout initialization, expansion, inline
   replies, and the fixed popup window height. Idle and reduced motion continue
   through the shared Motion policy.
4. Panel probe: construct every eligible targetScreen surface, detect component
   and runtime errors, keep windows unmapped, use private configuration/state,
   and clean up the exact child. Missing display coverage is an explicit skip.
5. Documentation: registration instructions agree with the fork's widget-key
   normalization and registry.
6. Run focused checks, `bash scripts/ci-lint.sh`, and
   `nix develop . --command bash scripts/check.sh`. Verify the unchanged settings
   contract against the deploying Nix module. Distinguish fixture/construction
   proof from interactive compositor behavior.

## Results

The implementation ICs used the approved gpt-5.6-luna/medium tier for the
calendar and Hyprland fixes, and gpt-5.6-terra/medium for each of notification
motion and the panel probe. Each was assigned specification and quality
self-review. The lead reviewed the actual patches and requested a separate
gpt-5.6-sol/high adversarial review of the combined changes. These are the
explicit dispatch settings; independent runtime model metadata is unavailable.

The panel runner adapts upstream by using the existing disposable project
helper, a private session bus, and disabled desktop-portal integration. It forces
the Wayland platform, accepts relative and absolute socket paths, and verifies
the exact completed surface count. `scripts/qmldir` registers the new probe.
The calendar and Hyprland changes retain upstream's selected behavior.

Live notification testing exposed an ineffective upstream animation:
`MotionBehavior on y` observed only the Column's final placement and did not
start its NumberAnimation. A minimal real Wayland probe reproduced the failure;
the same probe using `Column.move` produced 39 position samples. The first
adaptation used that transition with the original duration and easing.
Leaving `add` and `populate` unset preserved immediate placement for new and
returning cards without a readiness timer. This followed
[Qt's positioner transition contract](https://doc.qt.io/qt-6/qml-qtquick-column.html#move-prop).

Initial validation on 2026-09-18 (before the notification transition adaptation):

- `bash scripts/ci-lint.sh`: exit 0, passed.
- `nix develop . --command bash scripts/check.sh`: exit 0, zero failures and
  four existing warnings (optional powerprofilesctl, compositor autostart, and
  two Matugen configuration entries).
- Full checks include 200 QML files, 405 logic checks, 248 popup-coordinator
  checks, notification reload/disk tests, 165 settings states over 55 surfaces,
  and layout-fit checks. The new live Wayland panel check passed 12/12.
- Settings names and types match across GeneratedDefaults, ShellSettings, and
  `/home/olaolu/nixos-config/modules/home-manager/hyprland/modules/silere.nix`:
  53/53/53. No settings schema changed.
- Source-safe `qmllint --json -` with the repository import roots: the new
  panel probe and CalendarState have zero diagnostics. CompositorHyprland and
  NotificationPopups retain nine combined type-metadata diagnostics, identical
  by category/message to the base checkout; no new diagnostics.
- The supplemental Python QML scanner completed with heuristic findings.
  Dynamic component creation and variant handles in the probe follow the
  existing test harness, and slot timeout assignments are intentional state.
  Its output is not a clean lint result.
- `git diff --check`: passed. The seven changed code/registration files kept
  their hashes through the full gates.

The lead independently reran six calendar cases using production CalendarState
and PersistedFile in a disposable project: pre-load preservation, post-load
updates, missing files, future files, corrupt files, and unreadable files. All
passed. Removing the new guard in that disposable copy made the pre-load
preservation assertion fail, confirming that the check detects the original
bug. The production Hyprland backend passed eight fixture checks, including
modes 0/1/2 and both inert-event spellings. These use mocked backend inputs;
they do not claim a live maximize/fullscreen interaction test.

The maintained `scripts/test-notification-stack.sh` runs through the behavioral
suite. It copies and instruments the production popup in a disposable project,
uses a private session bus and files, and drives a real Wayland surface. The
test keeps the third notification hidden, removes the first, and separates
initial placement from movement at the retained card's reveal event. It checks
that the displaced card reaches zero and the returning card snaps in one step.
The lead's focused run passed with 35 intermediate position samples for normal
motion and none under reduced motion or the idle fixture. A copied child-Behavior
variant produces no intermediate movement, so the regression detects the
upstream implementation's failure. Idle input is a fixture, not a real desktop
idle transition.

Review tightened two initial test assertions: slicing out the first position
did not prove that initial placement snapped, and counting intermediates alone
did not prove the displaced card reached its destination. Those assertions
separate both phases and require the final position. No production adjustment
was made at that stage.

Validation before the external review, after the adaptation and assertion fixes:

- `bash scripts/ci-lint.sh`: exit 0, passed.
- `nix develop . --command bash scripts/check.sh`: exit 0, zero failures and
  the same four environment warnings. This run includes the maintained
  notification regression (35/0/0 intermediate samples) and 12/12 panel builds.
- Source-safe qmllint on the three changed production files and both new probes:
  exit 0; both probes clean, production diagnostics unchanged from the base.
  Probe entry points were relocated beside their imports, matching execution.
- The ten changed code/registration files retained their recorded hashes
  throughout the final gates. `git diff --check` passed.

The first adversarial reviewer completed the fixed-point review of all nine tracked
modifications and five untracked additions with no remaining high-confidence
findings across correctness, repository standards, and scope. It independently
reran the six calendar cases, Hyprland fixture, notification regression, and
12-panel probe. Real negative panel fixtures failed on both a missing QML type
and a runtime ReferenceError; both runtime runners explicitly skipped without
Wayland. Shell syntax and shellcheck passed. The lead accepted that
implementation after confirming the full gate's exit 0 and unchanged code
hashes. Both new shell runners have executable permissions, matching the
existing test scripts.

Claude's subsequent external review found a missed interaction: the move
transition restarts while a sibling's height animates. Its real Wayland traces
showed no lower-card movement during collapse or body expansion. Settling took
358 ms instead of 191 ms for dismissal, and 332 ms instead of 165 ms for
expansion. The lead independently checked the raw traces and confirmed those
measurements. The original maintained test covered instant D-Bus removal only,
so its passing result did not establish preservation of the animated paths.
That finding supersedes the earlier clean-review conclusion above.

The same review found missing entries for both new runners in
`scripts/README.md`. Both entries now describe their coverage and Wayland skip
condition.

The correction keeps the Column's layout position and animates a separate
visual position with a standalone NumberAnimation and Translate. It stops
that animation explicitly when a loaded card starts changing height, or when
idle/reduced-motion policy disables motion. New and returning slots become
eligible for movement only after the Column finishes positioning them.
This uses Qt's [independent translation](https://doc.qt.io/qt-6/qml-qtquick-translate.html)
and [positioning completion signal](https://doc.qt.io/qt-6/qml-qtquick-column.html#positioningComplete-signal).

The native move gate alone fixed the main stall but left active moves running
when expansion began. A private Wayland probe measured about 26 px of overlap
in that case. The standalone animation gives each slot explicit stop control.
The maintained test now observes visual position and covers body expansion
and timeout collapse with a retained hidden third card. Its number parser
accepts scientific notation, and its assertions allow subpixel rounding and
a bounded layout delay while rejecting material stalls or late movement.

The viewport and scroll content include the current visual bounds while cards
move. Otherwise removing a card shrinks the clipping region before the cards
below it reach their new positions. The screen-height cap and fixed popup
window height remain in place.

An independent private Wayland probe sampled after forcing pending layout.
Interrupted movement, simultaneous expansion and dismissal, and timeout
collapse with a hidden third card passed with zero measured position error
and overlap. The bounds check also passed; the interruption case needed up
to 64.739 px beyond the Column's target layout height during movement.
Pre-layout samples can fall between an upper height update and the following
Column layout, so those samples alone cannot establish rendered overlap.

Coverage limit: interruption during an active move and the count-shrink
clipping case are verified by disposable probes, not the maintained runner.
Removing the explicit stop handler or the visual-bounds calculation would
not fail the maintained tests today. The lead accepts this as a non-blocking
test-coverage gap; the independent probes establish the current behavior.

Final verification after the external review corrections:

- `bash scripts/ci-lint.sh`: exit 0.
- `nix develop . --command bash scripts/check.sh`: exit 0, zero failures,
  and the same four environmental warnings. Notification checks recorded
  35 normal movement samples, zero under reduced motion and the idle fixture,
  41 expansion samples, and 48 timeout-collapse samples. Both negative
  animation variants demonstrated their expected failures. Panels passed 12/12.
- Source-safe qmllint: exit 0, NotificationCard clean and NotificationPopups
  retaining its eight existing diagnostics. Other changed QML files retain
  their earlier valid type-check results; full compilation covers all 200 files.
- The supplemental Python scanner completed with findings, not a clean result.
  New private animation ids follow the file's existing underscore convention.
- All eleven changed code/registration files kept their recorded hashes through
  the final gates. The 53-key settings contract remains unchanged.
- The lead reviewed the final source and test assertions. The same approved
  Terra/medium IC and Sol/high reviewer handled this follow-up; actual runtime
  model metadata remains unavailable. The reviewer found no remaining production
  correctness or scope defects and retained the test-coverage concern above.
- QML review completed all six named analysis passes: bindings, layout, loaders,
  delegates, states/transitions, and performance. One reviewer performed the
  passes; these were not six independent agents. Performance coverage is static:
  the new scans traverse retained slots and filter for loaded or visible cards,
  with no frame-time benchmark claim.

Final gate logs are `/tmp/silere-claude-c1-final-ci-lint.log` and
`/tmp/silere-claude-c1-final-check.log`. The independent interruption, overlap,
and reveal traces are `/tmp/silere-explicit-visual-candidate/visual-*-matrix.log`.

## Follow-up re-review: reveal-all reset ordering

Claude's 2026-09-19 re-review confirmed C1, S1, and P1 resolved, then found C2.
After revealing three cards with a two-card limit, instant removal of the
first card lowered the service count before the Repeater updated its indices.
The early reveal-all reset briefly hid and reloaded the third card. It snapped
to its new position while the second card animated, producing 16 overlapping
frames and up to 64.74 px of overlap in the supplied trace. The lead checked
that trace independently.

The correction moves the reset to the Repeater's count change and defers it
with `Qt.callLater`. The callback reads the current count and current limit
after the model update completes. The existing immediate reset when the user
changes the visibility limit remains in place.

The maintained runner now reveals the third card only after the Repeater
contains all three, then instantly closes the first. It requires one reveal,
no subsequent unload of the retained third card, intermediate movement for
both retained cards, and a final reveal-all reset. Final positions must equal
the cumulative remaining slot heights, using measured heights rather than
a fixed pixel value.

Restoring the eager service-count reset in a disposable copy made this test
fail with duplicate reveal markers: `expected one retained-slot reveal:
[18, 27]`. A separate fresh Wayland probe of the correction passed across
302 samples after forcing pending layout: zero overlap, zero unscrolled
viewport overflow, no retained-card visibility flicker, and correct final
visual and cumulative layout positions. Its artifacts are in
`/tmp/silere-c2-green.daH5dR`; the failing copy is
`/tmp/silere-c2-eager-red.vJcape`.

Final C2 verification on 2026-09-19:

- `bash scripts/ci-lint.sh`: exit 0.
- `nix develop . --command bash scripts/check.sh`: exit 0, zero failures and
  the same four environmental warnings. The corrected reveal-all regression
  passed with 35 intermediate movement samples, alongside the existing
  notification cases, 12/12 panels, and the full surface and layout checks.
- Source-safe qmllint: exit 0, no new diagnostics. The Python QML scanner
  completed with its prior findings and no finding introduced by C2.
- The lead corrected a capture-group typo in the new final-height assertion;
  the successful behavioral gate exercised that corrected parser.
- IC self-review, lead review, and the independent review found no remaining
  C2 production defect. The reviewer updated all six QML analysis passes.
  The same approved Terra/medium and Sol/high configurations were used;
  runtime model identities remain unverified.
- The eleven code/registration hashes match
  `/tmp/silere-c2-final-manifest.json`. Other selected changes are unchanged.

Final gate logs are `/tmp/silere-c2-final-ci-lint.log` and
`/tmp/silere-c2-final-check.log`. Active-move interruption and visual-bounds
assertions still rely on the disposable evidence described above; the
maintained C2 test does not close that separate coverage gap.

Claude's final re-review, `/tmp/silere-review-c2-2026-09-19.md`, confirmed C2
resolved with no remaining confirmed production defect; C1, S1, and P1 remain
resolved. Fresh live probes verified the three-card reveal-all removal and
the four-to-three case, where reveal-all must remain enabled under a two-card
cap. Interruption and rapid-removal probes also remained clean.

Claude independently mutated disposable copies: restoring the eager reset
failed on duplicate reveal markers, and removing the reset failed because
reveal-all never returned to false. Its lint and maintained notification
runner passed, with unchanged qmllint diagnostics. It did not rerun the full
gate. The lead verified that all eleven code/registration hashes still match
the final C2 manifest, so the recorded full-gate evidence remains applicable.
The earlier disposable-only coverage gap remains accepted as non-blocking.
The report's output-label and deferred-callback teardown observations were
not classified as production defects; no implementation change followed.

The live panel check proves construction on Hyprland with unmapped surfaces,
not pointer interaction or visual correctness. Niri coverage remains the
existing mock-compositor tests. The production shell was not restarted.
The maintainer subsequently authorized focused commits; deployment remains
outside this work.

## Consistency check: 2026-09-19

The read-only consistency check covered all 16 changed files against the base,
including the five untracked additions. The implementation follows the existing
motion policy, probe helpers, and registration conventions. Comments explain
why notification displacement needs explicit animation control. The divergence
ledger, widget-registration instructions, and test inventory are updated.

The check found one minor diagnostic cleanup in `scripts/test-notification-stack.sh`:
the expansion-hook guard checked `card_source.count(expand_anchor)`, but its
failure message reported `card_source.count(card_anchor)`. The requested fix
was to report the count of `expand_anchor` so a missing or duplicated expansion
hook produces an accurate message. The guard itself checked the correct
anchor; this finding concerned failure reporting. The consistency check made
no code changes.

Fresh `bash scripts/ci-lint.sh` and `git diff --check` passed. The lint log is
`/tmp/silere-consistency-ci-lint.log`; no lint findings were discarded. The
cross-component motion and lifecycle changes warranted the deeper code and QML
reviews recorded above. This check found no reason to repeat them.

Claude's follow-up consistency report,
`/tmp/silere-consistency-2026-09-19.md`, identified two comments to clarify,
the undocumented `SILERE_PROBE_KEEP` option, and a duplicated normal-case label
in the show-all test output. Those are corrected, along with the earlier
expansion-anchor diagnostic. The retention option remains available for
investigation and is documented in `scripts/README.md`.

The lead retained the multiline height-animation declaration and its
`_heightAnimation` id. Exposing the animation's running state makes that block
more involved than its adjacent anonymous animations; a readable multiline
declaration does not need a deviation comment. Renaming the id to abbreviate
it would add churn without changing its meaning.

This follow-up changes QML comments, two test messages, and documentation.
It changes neither production behavior nor test assertions. Earlier full-gate
results describe the pre-cleanup source; the C2 manifest no longer matches
the popup and runner bytes.

Cleanup validation passed: `bash scripts/ci-lint.sh`, shell syntax, compilation
of all three embedded Python blocks, and `git diff --check`. The fresh lint
log is `/tmp/silere-consistency-cleanup-ci-lint.log`. The lead reviewed the
cleanup diff; no further adversarial pass or live motion rerun was warranted
for comments and test-message changes. The full runtime gate was not rerun.

## Commit validation: 2026-09-19

The maintainer authorized commits after the consistency cleanup. Each selected
upstream change landed separately, with source repository and full source SHA
in its commit message. Related divergence entries and test documentation landed
with their behavior changes.

| Commit | Change |
| --- | --- |
| `d74a479` | Protect calendar marks until the initial read. |
| `89a836f` | Distinguish Hyprland fullscreen from maximized windows. |
| `f85cdb1` | Correct the inert minimized-event name. |
| `94d3664` | Preserve notification stack motion through card changes. |
| `eea0754` | Build layer-shell surfaces in isolation. |
| `86a4873` | Document widget-key registration. |

Before each commit, the staged tree was copied into a disposable checkout and
its Git tree ID verified against the staged tree. Each snapshot passed
`bash scripts/ci-lint.sh` and `nix develop . --command bash scripts/check.sh`
with zero failures and the same four environment warnings. Settings names and
types matched across all 53 defaults, service properties, and Nix module entries.
The committed tree IDs were then checked against those validated snapshots.

The notification commit and later snapshots passed the maintained Wayland
motion regressions, including reveal-all shrink, height changes, idle and
reduced-motion gates, and both negative controls. The panel commit and the
widget-documentation snapshot passed all 12 panel construction checks. The
disposable-only interruption and clipping coverage limit remains unchanged.

Per-commit evidence is in `/tmp/silere-commit-20260919/`: steps 1 through 6
each have `.lint.log`, `.check.log`, `.tree`, and `.commit` files. This rerun
covers the consistency cleanup that followed the earlier C2 manifest.
