# Selective upstream integration plan: 2026-09-16

Status: stages 1–8 are implemented under the maintainer's authorization;
verification and the remaining interactive acceptance are tracked below.
Implementation started from `6b6eacfbabbf5e0981ffa3ab38f93a7c3d2098c8`.
The maintainer has now authorized committing stages 1–8 and proceeding to stage 9.
Commit preparation is in progress; deployment remains a maintainer action.
The execution record below tracks review and checks.
Stages 1–8 have completed implementation and automated verification; the
stage table names the remaining interactive checks. Stage 9 has an accepted
direction but is deferred until those changes have settled.

## Fixed points and prerequisites

- Source: [s3rven/silere-shell](https://github.com/s3rven/silere-shell).
- Upstream v1.0.0: `f17587c963664efad1b6a670d1340a32a9322ef1`.
  The fork's same-named tag identifies a different release.
- Reviewed upstream tip: `1c01251d597ff7d3ff673a9669b2fe087ab42f72`.
  The range contains 34 post-release commits.
- Fork HEAD at planning: `7f89b4a79a1e8cd3f12247f82c3e3cd00bc49b01`.
  Inspection also included the current working tree.
- At initial planning, uncommitted work spanned `PopupAnimation`, motion
  configuration, popup hosts/cards, and the divergence ledger. It subsequently
  landed in `6b6eacf` (shared system-panel fade and slide). Preserve that baseline
  when stages 6 or 9 touch popup surfaces; refresh HEAD before implementation.
  This records the commit's presence, not new runtime validation of that work.

Before implementation, refresh the fork status and record the actual stage
base. Retrieve exact source objects if necessary; do not substitute a moving
upstream tip. Follow [README.md](../README.md#selective-upstream-integration),
[AGENTS.md](../AGENTS.md), and the [divergence ledger](upstream-divergences.md).
This plan does not authorize a full upstream merge or assign subagents.

## Confirmed decisions

- Preserve upstream semantics where the fork has no established behavior or
  design. The standing rule lives in README's selective-integration policy.
  Existing fork behavior and recorded divergences still govern adaptations.
- Nix supplies the initial `notifHistoryPersistent` value; saved UI settings
  may override it. This follows the existing Nix defaults mechanism rather
  than adding an enforced policy.
- Keep upstream's persistence-off behavior: clear existing history, queue an
  empty history array to disk, and allow subsequent in-memory history until
  reload or process exit. The file is not deleted and read/timestamp metadata
  can remain. Do not add session-history retention across reloads while off.
  Our current `Notifications._applyHistorySettings()` and toggle handler
  already clear existing history and retain new arrivals only until reload,
  so this choice also preserves the fork's existing interaction.
- Apply the same rule to Wi-Fi/Bluetooth forgetting: retain upstream's guarded
  middle-click gesture. The fork has no existing forget action; its details
  drawers currently serve connected entries. Do not expand those drawers or
  add a new Forget presentation as part of this import. Reuse the fork's
  existing confirmation machinery where compatible with the gesture.
- Standardize all eight coordinated control-popup states on a common
  abstraction, following upstream's consolidation direction while accommodating
  necessary fork deviations. This includes centered and bar-anchored popups.
  Defer this work to stage 9 after stages 1–8 have landed and settled; the
  implementation shape and anchor-loss policy will be resolved at that point.

These decisions were confirmed during planning. Evidence: S10's
`Notifications.qml` toggle/save/restore paths,
the fork's `services/Notifications.qml`, and the defaults contract documented
in nixos-config's `modules/home-manager/hyprland/modules/silere.nix`.

## Sequence and tracking

Stage 1 groups small tasks for scheduling, not into one combined commit.
Keep one coherent task per commit when commits are authorized. A mixed
upstream commit can supply several local commits; each records its full source
SHA and the selected behavior. Source labels resolve to full SHAs below.

| Stage | Scope | Prerequisites | Status / local commits |
| --- | --- | --- | --- |
| 1 | Small fixes and lint | Refresh baseline | Implemented, uncommitted; automated checks pass; visual acceptance remains |
| 2 | Tool and hook probe recovery | Stage 1 error helper | Implemented, uncommitted; probes and permission-failure reproduction pass |
| 3 | Wi-Fi security and forget action | Stage 1 shared controls | Implemented, uncommitted; backend probes and real Apt532 forget check pass |
| 4 | Bluetooth blocking, pairing, and forget action | Stage 1; stage 3 recommended for gesture consistency | Implemented, uncommitted; backend probes and real Sony XM5 forget check pass |
| 5 | Audio volume-limit correction | Stage 1; preserve fork audio contract | Implemented, uncommitted; logic checks pass; live audio check remains |
| 6 | Nested tray navigation | Existing popup work reconciled | Implemented, uncommitted; rendered mock and hover-chain/control probes pass; physical pointer check remains |
| 7 | Disk history and Nix default | Stage 1 notification identity fix; paired nixos-config work | Implemented, uncommitted; restart/reload/error probes and Nix evaluation pass |
| 8 | Shared fullscreen state | Stable notification/OSD baseline | Implemented, uncommitted; mock demand checks and one-off Hyprland check pass |
| 9 | Common popup abstraction and registration | Stages 1–8 completed and settled; settled popup baseline | Deferred; direction accepted |

This is the recommended order, not a claim that every stage depends on all
earlier stages. Stages 2–5 can be reordered after stage 1. Stage 8 is separable
from stage 7; doing it afterward keeps changes to `Notifications.qml` easier
to review. Stage 9 is explicitly deferred; no abstraction migration is required
to complete stages 1–8. Revisit it after their acceptance checks pass and any
resulting popup regressions have been resolved.

## Stage 1: small fixes and lint

Each row is a separate bounded task.

| Task | Source | Scope and acceptance |
| --- | --- | --- |
| Shared error-line helper | S1 | Add `SafeText.lastNonEmptyLine`; update brightness and the fork's command-based power-profile callers. Check trailing blanks, CRLF, fallback, and bounded sanitized text. Preserve `asusctl`. |
| Internal-type lint | S2 | Check existing internal declarations. Verify an illegal cross-module use fails and valid uses/path references pass. Audit false positives in comments/test fixtures. No bulk `qmldir` privatization. |
| Level-track inset | S3 | Apply the `Pill` geometry correction. Check compact/normal widths, interface scales, and hover/pressed states; retain our radius policy. |
| Faded glow/rim visibility | S4 | Hide fully faded elements. Verify fade-out/fade-in, palette changes, and reduced motion. Do not claim measured performance gains. |
| Wheel-direction reversal | S5 | Port only `Scroll.qml`'s accumulator reversal change. Check wheel/touchpad reversal and retained throttling. |
| Confirmation cancellation | S5 | Port `ConfirmButton`'s enabled/busy guards and disarming. Check disable, busy, hide, re-enable, and accessibility activation after arming. |
| List scroll indicators | S5 | Port `originY` corrections in `ListEdgeLines` and `MenuScrollThumb` together. Check removal while scrolled, empty lists, and both ends. |
| Short app-name matching | S5 | Port the suffix-match length guard in `WindowActions`. Short names must not suffix-match unrelated windows; exact matches must still work. |
| Playback-rate progress | S6 | Port `Media.extrapolatedPosition`, its caller, and rate-change reanchoring. Check pause/play, 0.5x/1x/2x, seeking, rate changes, invalid rates, and duration bounds. Preserve media-popup demand. |
| Notification deletion identity | S6 | Port the stronger history-entry match. Check equal time/summary with different IDs/apps; deleting one must preserve the other and live state. |

Use existing probes for meaningful behavioral regressions. Geometry/visibility
changes need focused visual checks, not tests that repeat their formulas.
Do not take all of S5 or S6 to obtain these tasks.

## Stage 2: tool and hook probe recovery

Source: S7, limited to `SystemTools.qml`, `Hooks.qml`, and applicable probes.

Retain the last successful tool/hook set on failed or timed-out scans. Add
bounded retry backoff and reset it after success. Take the separate critical-
battery hook allowance and slower descendant polling while preserving the
process-group deadline and zombie handling. Exclude updater and process-based
night-light changes; our systemd backend remains.

Verify initial failure, failure after success, partial hook scans, repeated
timeouts, and eventual success/removal. A successful scan must still remove
disappeared capabilities; an initial failure must not invent availability.
Verify normal hook flooding cannot consume the reserved critical allowance,
and that allowance remains rate-limited. The `07d23db` performance bundle is
outside this stage.

## Stage 3: Wi-Fi security and forget action

Source: S8. Port into the existing `Network` service and Wi-Fi list.

Classify passwordless, PSK, and stored-profile-only security types; restrict
password entry/`connectWithPsk` accordingly. Add guarded middle-click forgetting
for inactive saved networks. Preserve details, band selection, stable lists
while typing, and the external editor action.

Use the confirmed upstream gesture; no separate interaction-design artifact
is required before this stage. Check the resulting states in the real shell.

Verify the pinned Quickshell API supports the referenced enums/methods. Cover
open/OWE, PSK/SAE, known/unknown enterprise/WEP, wrong-password retry, active-
network restrictions, and forget confirmation. Label fixtures for unavailable
network types. Use a suitable test network/profile for live verification.

## Stage 4: Bluetooth blocking, pairing, and forget action

Source: S9. Preserve `BluetoothDetails`, connection-event selection cleanup,
and the actionable bar widget while porting service/list behavior.

Surface hardware blocking in Home and quick actions. Add guarded forgetting
for disconnected paired devices. Keep attempts alive while BlueZ reports
pairing. Disconnect/cancel/forget must clear only the matching device's attempt
and error.

Use the same confirmed forgetting gesture as Wi-Fi. Preserve the fork's
existing confirmation patterns rather than adding an unrelated UI design.

Verify the pinned adapter/device API, blocked/unblocked controls, pairing
beyond 20 seconds, disconnecting A while pairing B, failure/retry, and forget
confirmation. Check Home and quick actions together. Label hardware fixtures
separately from real device interaction; use a test device for forgetting.

## Stage 5: audio volume-limit correction

Source: S5's `PwVolumeControl` fix, adapted into the fork's `Audio.qml`.

Port raw-backend-volume comparison and finite-value guards into corresponding
paths. Preserve the audio service, microphone controls, sound settings, and
`audio` IPC. Do not introduce `PwVolumeControl` or replace the fork backend.

Verify amplified backend values above 1.0, setting exactly 1.0, invalid values,
pending writes/retries, device changes, mute, and scrolling. Check the existing
microphone/source policy remains intact. Use controlled fixtures for extreme
values and ordinary levels for live speaker/microphone checks.

## Stage 6: nested tray navigation

Sources: S6's `TrayMenuState.branchHovered`, plus S5's `Metrics.flyoutX` and
`TrayMenuPopup` changes. Import these as one coherent behavior change.

Keep parent flyouts open while entering descendants and clamp placement to
screen edges. Adapt to the settled popup-animation work. Preserve click-based
submenu expansion, overflow navigation, inline tray, and the tray-list child
exception in `OverlayCoordinator`.

Implementation adaptation: retain the fork's existing `_flyoutLaneFits`,
drill-in navigation, and root overlay placement. These already handle screen
edges and ancestor overlap. S5's simpler `Metrics.flyoutX` has no production
caller here and is not imported. The selected hover-chain fix uses that
existing geometry and keeps click-opened drill-in navigation out of hover close.

Verify multiple submenu levels, entering/leaving descendants, screen edges,
scrolling, activation, and closing through both inline-tray and tray-popup
entry points. A mock tray menu may supply the hierarchy; verify its displayed
behavior in the disposable Hyprland shell.

## Stage 7: disk notification history and Nix default

Sources: S10 plus notification/calendar portions of S11. This is paired work
in the shell and nixos-config. Keep the fork's stronger settings-migration
backup implementation; do not import S11's visualizer settings.

1. Reuse `PersistedFile`/`ConfigStore` for disk storage and permissions. Preserve
   reload restoration order, live session identity, deferred orphan pruning,
   and settings-read gating.
2. Reconcile disk, reload, and new live entries without duplicates or stale-ID
   actions. An entry from another process cannot target a reused current ID.
   Preserve grouped-history expansion behavior.
3. Include newer-format-file protection, bounded restoration, and pending-save
   handling from S11. Calendar version protection is a separate bounded task
   in this stage. Preserve corrupt/unreadable files.
4. Expose the existing `notifHistoryPersistent` through
   `local.hyprland.silere.notifHistoryPersistent`. Add its `GeneratedDefaults`
   value/reference and Nix option/render together; keep the stock default
   value. Update UI wording from reload persistence to restart persistence.

Use the confirmed Nix-default and persistence-off semantics above. Preserve
upstream's empty-history disk write rather than introducing file deletion or
retention through reloads while persistence is off. No overlapping second
setting is needed. Retain protections for unreadable and future-version files;
acceptance must distinguish a successful clearing write from a blocked or
failed write, rather than claiming disk history was cleared unconditionally.

Verify with private config/state directories and a private notification bus:
two fresh processes sharing history, a real QML reload, live arrival during
restoration, reused IDs, seen/time state, retention/limits, disabling and
re-enabling persistence, malformed/future files, failed writes/retries,
permissions, and pending writes during reload/shutdown. Document any debounce
loss window; do not claim crash-proof saving.

Check key names/types and the three-way defaults count. Evaluate the Nix
renderer and follow README's coupled deployment ordering. Evaluation alone
does not prove activated behavior; maintainer-only operations stay with the
maintainer.

## Stage 8: shared fullscreen state

Source: S6's `FullscreenState` extraction and notification/OSD consumers.

Move shared fullscreen demand out of `Notifications` while retaining current
behavior. The fork removed the visualizer and `mediaProgress`; exclude that
demand term and its pause timers. Exclude upstream auto-night-light startup
changes. Preserve the shared compositor boundary.

Verify silence and integrated OSD independently, both enabled/disabled,
enabling demand while already fullscreen, changing active windows, and exiting
fullscreen. Floating OSD alone must not request tracking. Search for stale
consumers of the old notification API. Verify Hyprland live; retain labeled
Niri static/mock coverage.

## Stage 9: common popup abstraction and registration (deferred)

Direction accepted by the maintainer: standardize coordinated popup state and
lifecycle through one common abstraction, accommodating deviations where
necessary. Source: S6's popup registry, adapted to the fork. Upstream places
registration in `AnchoredPopupState`; our scope also includes centered popups,
so adopting that class unchanged is not the complete design.

Revisit after stages 1–8 are complete, their acceptance checks pass, and any
resulting regressions have been resolved. Refresh the implementation baseline
then. Do not expand earlier stages into this migration. Keep this stage in the
same plan so deferral does not lose the agreed direction.

### Common responsibility and scope

Cover menu, calendar, tray menu/list, quick actions, keybindings, wallpapers,
and media. Standardize shared open/close lifecycle, registry participation,
and coordination instead of retaining independent copies in the four fork
states. Keep feature-specific state/content with its feature. This scope is
the eight coordinated control popups, not notification delivery or the OSD.

Preserve these differences explicitly:

- Keybindings and wallpapers use centered placement without a bar anchor.
  Common lifecycle must not require a fictitious anchor or change placement.
- Media and the tray list are anchored. Retain closure when media disappears
  or the tray becomes empty. Consolidate duplicated anchor mechanics only
  after resolving their anchor-loss behavior below.
- A tray context menu opened from the tray list may coexist with its parent;
  unrelated control popups remain exclusive.
- Preserve idle/overview late-open rejection, cold-start IPC availability,
  screen targeting, and the existing anchor-recovery behavior of current
  `AnchoredPopupState` consumers.
- Preserve `ControlSurfaces.opened` or migrate its command-based power-profile
  consumer explicitly in the same task. Keep the existing control-surface
  classification and service demand semantics.
- Retain the settled shared popup animation and layer-shell namespaces.

### Design decisions deferred with implementation

The direction is settled; these mechanics require the post-stage-8 code:

1. Choose the smallest shared abstraction that supports both centered and
   anchored states. Prefer extending existing code; decide whether placement
   belongs in a specialization or an explicit capability. Do not prescribe a
   new hierarchy or make every popup carry unused anchor machinery now.
2. Resolve anchor loss for media/tray: they currently close immediately, while
   `AnchoredPopupState` allows 150 ms for anchor replacement. Decide whether
   to adopt recovery or preserve immediate closure as an explicit deviation.
   Do not change this behavior as an incidental consequence of inheritance.
3. Define how necessary exceptions, particularly the tray parent/child relation,
   are expressed without rebuilding a second list of popup-specific branches.
   Avoid a general extension system unless the actual cases require one.

At resumption, review these choices against the actual consumers with the
maintainer; do not reopen the already accepted consolidation objective.

### Acceptance

Verify every open path and pairwise exclusivity, with the tray child exception
checked separately. Cover cold IPC opens, rapid toggles, close-during-open,
reload, idle/overview late opens, recreated anchors, media/tray disappearance,
centered versus anchored placement, and power-profile refresh on reopening.
Check registration/open counts and the chosen anchor-loss policy. Confirm
each coordinated state uses the common lifecycle and every remaining
deviation has a concrete reason. Do not claim a line-count reduction before
comparing the final implementation.

Evidence for the current split: `services/AnchoredPopupState.qml`,
`KeybindsPopupState.qml`, `WallpapersPopupState.qml`, `MediaPopupState.qml`,
`TrayPopupState.qml`, `OverlayCoordinator.qml`, and `ControlSurfaces.qml`.
The four fork states predate upstream's base extraction in
`b108a48e0d68c8c34638e7f6814b8bf52163f8cd`; their separate implementations do
not by themselves establish a requirement to remain separate.

## Completion gates and execution record

For each task, record the actual base, full source SHAs, local commits when
authorized, adaptations, checks, runtime coverage, and remaining limitations.
Update the stage table after acceptance; a clean patch application or source
inspection does not complete a stage.

- Run `bash scripts/ci-lint.sh`, then
  `nix develop . --command bash scripts/check.sh` before every commit as required
  by AGENTS.md. Require zero failures and investigate changed warnings.
- Preserve the settings contract; only stage 7 intentionally expands its key
  set and requires paired Nix rendering changes.
- Load `qt-qml` before QML edits. Complete repository-local `qt-qml-review`
  after substantial QML changes. Follow the maintainer's dispatch approval
  and model-selection policy if that review uses subagents.
- Update the divergence ledger with the commit changing a standing divergence.
  Preserve removed updater, distribution, and visualizer paths.
- Use disposable instances for interactive checks. Never restart production.
  Distinguish static checks, fixtures, isolated runtime, and live Hyprland
  evidence. Do not claim live Niri coverage from mocks.

Append results in this format:

```text
Stage/task:
Actual fork base:
Full upstream source SHA(s):
Local commit(s), or uncommitted status:
Adaptations and ledger changes:
Static/probe results:
Live coverage and limitations:
Remaining work:
```

### Implementation record

All stages use base `6b6eacfbabbf5e0981ffa3ab38f93a7c3d2098c8` and the exact
source SHAs in the table below. There are no new commits or deployments.
The paired Nix edit is
`~/nixos-config/modules/home-manager/hyprland/modules/silere.nix`.

| Stage | Implemented adaptation and evidence |
| --- | --- |
| 1 | Error helper, scroll reversal, short-name matching, rate-aware media progress, raw volume comparison, confirmation cancellation, inset/fade/originY corrections, identity-safe notification deletion. The internal-type checker masks comments/strings and excludes probes relocated by their runners; portability fixtures check accepted and rejected references. |
| 2 | Failed tool scans retain capability revision as well as the last answer. Hook failures retain the last complete set and retry; missing directories still mean empty. A private chmod failure/recovery reproduction independently verified retention, 5000 ms backoff, and reset on success. Critical hooks have a bounded separate allowance. |
| 3–4 | Retained ScriptModel freeze, details drawers, ArmConfirm, and the actionable Bluetooth widget. Backend fixtures exercise actual service methods for PSK dispatch, guarded forget, pairing timeout continuation, and device-specific cleanup. The timer fixture shortens the interval to 40 ms. Real NetworkManager and BlueZ forget tests passed after the identity-race correction documented below. |
| 5 | Adapted upstream volume comparison into Audio. The finite raw-volume helper is covered by the service probe; actual PipeWire device/retry behavior remains a live acceptance item. |
| 6 | Added descendant-hover retention around existing adaptive flyout placement and PopupAnimation. The checked-in tray probe covers ancestor traversal and shared confirmation cancellation. A separate disposable Hyprland instance rendered the real popup with synthetic menu/hover inputs, checked actual close timers and screen-fit geometry, and captured both nested flyouts. Physical pointer movement, both entry points, and edge/overflow variants still need acceptance. A width-binding warning in the synthetic popup also reproduced on the untouched baseline. |
| 7 | Reused ConfigStore/PersistedFile. Reload state takes precedence over disk, including cleared history; disk merges wait for saved settings. A PersistentProperties marker prevents stale disk restoration during an engine handoff. The notification divergence entry documents session identity, storage, and persistence-off behavior. |
| 8 | Extracted FullscreenState with exactly notification-silence and enabled integrated-OSD demand. The mock probe covers eight demand/state transitions. A disposable Hyprland window verified demand enabling while fullscreen and fullscreen exit. Its temporary runner was discarded because focus then fullscreen were separate operations; it is not a reusable automated gate. Niri coverage remains mock/static. |

The adversarial review reproduced and independently retested three fixes:
non-timeout hook scan failure, a false Nix default overridden by saved true
settings, and history clearing immediately before a real QML reload. The
notification disk runner now retains the two persistence regressions.

The three-way settings contract has 53 matching property names/types in
GeneratedDefaults and the Nix renderer, and 53 ShellSettings references.
`nixfmt --check modules/home-manager/hyprland/modules/silere.nix` passed.
`nix eval --raw '.#homeConfigurations."olaolu@boreas".activationPackage.drvPath'`
passed in nixos-config. This evaluates the option/renderer integration with
the existing lock; the shell input has not been re-locked or activated.

`bash scripts/ci-lint.sh` and
`nix develop . --command bash scripts/check.sh` passed on the integrated tree.
The latter compiled/import-checked 199 QML files, ran the full behavioral suite,
loaded surface/accessibility/scale variants, swept 165 states over 55 surfaces,
and passed layout checks. Its four warnings match the pristine base: optional
powerprofilesctl, installer-style autostart discovery, and two Matugen setup
checks. Nix manages those deployment paths separately.

### Review completion and live connectivity results

All three implementation ICs reviewed their changes, followed by lead review.
The independent adversarial review and all six focused QML review missions
completed. Actual model assignments were:

| Role | Actual model / reasoning |
| --- | --- |
| Persistence IC | gpt-5.6-terra / high |
| Service IC; UI/connectivity IC | gpt-5.6-terra / medium |
| Bindings, lifecycle, delegates, states, performance reviewers | gpt-5.6-sol / high |
| Layout review | gpt-5.6-terra / medium, reused UI IC |
| Independent adversarial reviewer | gpt-6-astra / high |

The lead resolved these additional review findings:

- Rebuild live notification IDs from the server after reload, so a notification
  rejected by DND cannot leave a retained live marker. A real notification,
  DND toggle, and QML reload independently verified pruning.
- Keep explicitly opened tray flyouts open until hover has entered them.
  The disposable production-popup fixture verified explicit opening without
  hover, ancestor retention through descendants, and closing after leaving.
- Give both forget confirmations precedence over stale failure coloring.
- Restart a consumed retry timer when a timed-out tool process finally exits.
  This is defensive coverage of a delayed process exit; no stalled-process
  reproduction established the reviewer's suspected timing window.

The maintainer designated Apt532 and Sony WH-1000XM5 as disposable targets,
then switched to a hotspot. Disposable offscreen windows loaded the actual
list components and services against the real NetworkManager and BlueZ buses.
The tests invoked the production middle-tap handlers, checked the first press
kept the target and showed warning confirmation despite a stale error, then
confirmed on the second press. They did not simulate physical pointer input.

The first Wi-Fi run exposed a synchronous identity race: disarming confirmation
unfroze the list, changed the delegate's model, and sent a different SSID to
`forgetWifi`. That other network was unknown, so the service guard rejected it.
Capturing identity before confirmation fixed it. The connectivity-path runner
now checks 14 cases, including four actual-row reentrancy regressions for
forget and body activation in both lists. Restoring the faulty Wi-Fi expression
in a disposable copy failed the new identity check; the corrected code passed. The same precaution applies
to Bluetooth, and body activation retains its original row when dismissing
an armed forget prompt. The fixed Wi-Fi run removed Apt532, and the Bluetooth
run removed the Sony pairing. Independent `nmcli` and `bluetoothctl` reads
confirmed both removals and that the hotspot stayed connected.

Scratch evidence: `/tmp/silere-live-forget/run-wifi-trace.log`,
`run-wifi-fixed.log`, and `run-v2.log`. These are session diagnostics, not
portable automated tests. Backend fixtures retain security, pairing-timeout,
and guard coverage; neither these fixtures nor the offscreen windows prove
hardware-block-switch behavior or the complete pointer/visual matrix.

Remaining interactive acceptance is explicit in the stage table; automated
coverage does not establish those interactions.

## QML Code Review Report

**Scope**: working-tree diff from `6b6eacfbabbf5e0981ffa3ab38f93a7c3d2098c8`,
including new QML probes.
**Files reviewed**: 41.
**Issues found**: no unresolved confirmed defects; four QML/runtime defects
were corrected, as detailed above and below.
**Python lint**: completed with findings, exit 1. Command:
`python3 .agents/skills/qt-qml-review/references/lint-scripts/qt_qml_lint.py <changed QML paths>`.
The exact path list and output are in `/tmp/silere-review-files.txt` and
`/tmp/silere-qml-python-lint.log`.
**qmllint**: completed with findings, exit 0. Command:
`nix develop . --command bash /tmp/silere-qmllint-production.sh`.
The script runs `qmllint --json -` with the repository and pinned module imports
against the production subset. JSON is in `/tmp/silere-qmllint-production.json`.
Probe imports are relocated by their runners and verified there; they are not
claimed as a clean standalone qmllint run.
**Runtime checks**: integrated checks and focused probes are recorded above;
the final post-review gate result is recorded below.
**Deep-analysis coverage**: 6/6 complete. The new identity correction received
an additional delegate review and regression check.

### Lint findings

Generic Python diagnostics flag declaration order, underscore-prefixed private
IDs, mutable maps stored as `var`, and IDs on minimal fixture singletons. These
follow the surrounding repository or fixture patterns. Its loose-equality
matcher also flags existing strict `!==` expressions. Retain local conventions
and the intentional dynamic maps rather than rewriting them for these checks.
The changed-line qmllint diagnostic is the pinned module's missing
`QProcess::ExitStatus` metadata for Hooks' exit signal. The real process paths
compile and execute in the runtime suite. Neither tool's exit status is treated
as proof that its diagnostic output was empty.

### Deep analysis findings

| Finding | Location | Category / confidence | Resolution and evidence |
| --- | --- | --- | --- |
| Stale live IDs after DND reload | `services/Notifications.qml`, deferred server handoff | Bindings / reproduced | Rebuild from tracked server objects; actual notification and reload verified pruning. |
| Explicit tray flyout closes without hover | `modules/traymenu/TrayMenuPopup.qml`, close timer | Delegates / reproduced | Require hover entry before hover-driven closure; four production-popup fixture checks passed. |
| Failure tint overrides armed forget | `modules/menu/WifiList.qml` and `BluetoothList.qml`, `failed` bindings | States / reproduced | Exclude both confirmation arms; both live forget probes verified warning styling despite a stale error. |
| Confirmation retargets a replaced delegate | Same list files, activation handlers | Lead runtime review / reproduced | Capture target before disarming; actual Apt532 removal passed and synthetic row replacement guards against recurrence. |

### Investigation targets (human verification needed)

The delegate reviewer noted a pre-existing possibility that a security change
while the Wi-Fi list is frozen leaves a stale password drawer (74/100).
The service still checks current security before passing a PSK, so the suspected
impact is stale UI. This requires a network whose security changes while the
drawer is open; no such live scenario was tested. It is not a prerequisite for
these imports. The lifecycle review's delayed-timeout-exit concern was hardened
as described above without claiming a reproduction.

### Summary

| Category | Confirmed defects resolved | Open investigation targets |
| --- | --- | --- |
| Bindings | 1 | 0 |
| Layout | 0 | 0 |
| Lifecycle | 0 | 0 |
| Delegates, including live follow-up | 2 | 1 |
| States | 1 | 0 |
| Performance | 0 | 0 |
| Total | 4 | 1 |

### Verification before the independent Claude review

After the final identity fixes and regression additions:

- `bash scripts/ci-lint.sh`: exit 0, lint passed.
- `nix develop . --command bash scripts/check.sh`: exit 0, zero failures and
  the same four baseline warnings. All 199 QML files compiled/imported, the
  connectivity runner passed 14 checks, and disk persistence passed 22 checks.
  Startup, 36 default-off settings, six malformed settings cases, surface
  variants, the 165-state/55-surface sweep, and layout checks passed.
- Final production `qmllint`: exit 0 with the diagnostics described above.
  Python lint completed with convention/heuristic findings, exit 1; it is not
  represented as a clean check.
- `git diff --check`: exit 0. No commit or deployment was performed.

Full gate logs are `/tmp/silere-final-frozen-lint.log` and
`/tmp/silere-final-frozen-check.log`. The service IC self-reviewed the final
identity fixes; the delegate reviewer independently inspected and tested them;
the lead reviewed both the fix and the regression. The existing independent
adversarial review plus this targeted follow-up was sufficient; no additional
broad adversarial pass was warranted for the final local-variable changes.

### Independent Claude review follow-up

Claude's independent review is `/tmp/silere-adversarial-review-2026-09-16.md`,
against `6b6eacfbabbf5e0981ffa3ab38f93a7c3d2098c8`. The maintainer authorized
fixes and a response report. This follow-up addresses these findings:

- **C1:** Single-row and run deletion no longer suppress the pending disk
  archive. Clear-all and persistence-off retain that suppression. The regression
  runner copies the production services into a disposable project and holds the
  real file-load callback before merging. Row/run deletion must preserve three
  seeded disk rows and one surviving current row, both in memory and in the
  subsequently written file; clear-all must leave both empty. The row case failed
  before the fix. All three cases pass afterward. This controls event ordering;
  it does not establish how often the window occurs during normal UI startup.
- **P1:** Newer-format notification files now restore compatible entries and
  seen/time state into memory, with disk writes blocked. This follows upstream
  S11 and the standing semantics rule in README. Tests check prior-process row
  identity, persistence-off behavior, and byte-for-byte preservation of the
  future file, including unknown fields, after in-memory edits. The restore test
  failed before the fix. The divergence ledger describes the resulting behavior.
- **S1:** The ledger now records the tray's adaptive lane placement, drill-in
  navigation, and root-lane overlays as behavior to preserve during future picks.
- **Cleanup:** Removed unused `SystemTools.refreshIfStale()` and its timestamp,
  plus the unread `passwordless` Wi-Fi row field and fixture copies. The security
  helper retains its own derivation and return field.
- **S2:** Retained the shared `PersistedFile` permission-hardening path. The
  extra chmod process per successful debounced write is an acknowledged cost;
  permission caching remains deferred without measured need.

The old-engine flush-ordering and non-finite PipeWire-volume possibilities remain
unverified investigation targets. Existing interactive acceptance gaps and the
deferred stage 9 are unchanged. No production-shell restart, live device forget,
commit, or deployment is part of this follow-up.

Follow-up gates pass: `bash scripts/ci-lint.sh` and
`nix develop . --command bash scripts/check.sh` both exit 0. The full suite
reports the same four baseline warnings, 199 compiled/imported QML files,
35 disk-probe checks (plus file assertions), 14 connectivity-path checks, and
165 states over 55 surfaces. `git diff --check` passes. The settings property
counts remain 53/53/53; the paired Nix module was not changed by this follow-up.
Logs are `/tmp/silere-claude-followup-lint.log` and
`/tmp/silere-claude-followup-check.log`. The detailed response is
`/tmp/silere-adversarial-followup-2026-09-16.md`.

The cleanup IC self-reviewed; the lead reviewed all follow-up edits. The reused
bindings reviewer independently inspected C1/P1 and the probe seam and reported
no concerns. Runtime evidence comes from the lead's successful runs; the
reviewer's own runner attempt did not launch after an approval timeout. Focused
review was sufficient for this delta. Both reused agents report GPT-6 at runtime
with no exposed reasoning tier, rather than the earlier planned terra/medium and
sol/high assignments; independent dispatch metadata is unavailable here.

### Independent Fable re-review

Fable's `/tmp/silere-adversarial-rereview-2026-09-16.md` confirms C1/P1, the S1
ledger entry, the retained S2 cost, and both cleanups, with no new defects.
It reports independent passing lint, all 15 disk phases (35 checks plus file
assertions), and connectivity/service probes (8/14/11 checks). Disposable-copy
revert experiments make `delayed-row` fail when C1 is reverted and `future`
fail when P1 is reverted. These results are attributed to Fable's report.

The lead confirmed `historyPersistenceError` has no consumer under `modules/`
and changed the probe label from "visible" to "reported". This corrects the
coverage description; no UI or runtime behavior changed. The earlier 22-check
record is historical; the current disk suite has 35 checks. Existing interactive
acceptance gaps and unverified investigation targets remain unchanged.

## Selected source commits

| Label | Exact upstream commit | Planned use |
| --- | --- | --- |
| S1 | [4f27c01dab2078a163d7f46fef96034575b53ad7](https://github.com/s3rven/silere-shell/commit/4f27c01dab2078a163d7f46fef96034575b53ad7) | Error helper; stage 1 |
| S2 | [1fec69374350492ef46c89dbd8d8561c04447d12](https://github.com/s3rven/silere-shell/commit/1fec69374350492ef46c89dbd8d8561c04447d12) | Internal-type lint; stage 1 |
| S3 | [502547b02279553b71ae13a5ec480d8ed4a17d3f](https://github.com/s3rven/silere-shell/commit/502547b02279553b71ae13a5ec480d8ed4a17d3f) | Level-track inset; stage 1 |
| S4 | [d5f18aaf48a95a27c4c69c0bc02429b9fbe93c53](https://github.com/s3rven/silere-shell/commit/d5f18aaf48a95a27c4c69c0bc02429b9fbe93c53) | Faded visibility; stage 1 |
| S5 | [066e7f42d2e66bf8158947fd6c68ef61e23adcaf](https://github.com/s3rven/silere-shell/commit/066e7f42d2e66bf8158947fd6c68ef61e23adcaf) | Selected fixes; stages 1, 5, 6 |
| S6 | [cfdeff3e1a932de05162f7591dedc8e8c6656cf6](https://github.com/s3rven/silere-shell/commit/cfdeff3e1a932de05162f7591dedc8e8c6656cf6) | Selected fixes/refactors; stages 1, 6, 8, 9 |
| S7 | [ba2d29ff02b81f8857e9bdb0ea54e866acc000c3](https://github.com/s3rven/silere-shell/commit/ba2d29ff02b81f8857e9bdb0ea54e866acc000c3) | Tool/hook recovery; stage 2; duplicate request deduplicated |
| S8 | [b0a5519b6a52a72632d06b9a762394179c893b93](https://github.com/s3rven/silere-shell/commit/b0a5519b6a52a72632d06b9a762394179c893b93) | Wi-Fi; stage 3 |
| S9 | [1d0769e465d0c78e7350ef2c45dcd17d854a5554](https://github.com/s3rven/silere-shell/commit/1d0769e465d0c78e7350ef2c45dcd17d854a5554) | Bluetooth; stage 4 |
| S10 | [5ba33ba9bf4f748a068da590b4c146b16ceea7e1](https://github.com/s3rven/silere-shell/commit/5ba33ba9bf4f748a068da590b4c146b16ceea7e1) | Disk history; stage 7 |
| S11 | [35921c167fedde3061c6663168e74d5b1a0b709a](https://github.com/s3rven/silere-shell/commit/35921c167fedde3061c6663168e74d5b1a0b709a) | Notification/calendar protection; stage 7 |

## Deferred, excluded, or already covered

These dispositions apply to the reviewed range. Short hashes resolve within
its fixed history. Deferred items require their own selection/review; being
earlier in upstream history does not make them prerequisites.

| Commit(s) | Disposition |
| --- | --- |
| `13acda0` | Already adapted; see the [September 9 record](upstream-picks-2026-09-09.md). Preserve continuous bump retriggering. |
| `5b68d7b` | Concurrent smoke execution remains unselected, consistent with that record. |
| `ac9863d` | Defer notification app rail, a separate UX change against grouped history. |
| `2f05c68`, `369c748` | Exclude visualizer work; Cava remains removed. |
| `bdfa1e6` | Defer Home power-profile picker changes; retain command backend and current controls. |
| `43d4b4e`, `37e8735`, `d9b4b30`, `1c01251` | Defer notification width, row-corner, and maintenance presentation changes. |
| `f921826` | No wholesale pick: the fork already has threshold-settled battery alerts. Other differences need separate justification. |
| `4fb1c11` | Defer modified-setting-dot visibility cleanup. |
| `7119084` | Defer expanded internal declarations pending fork consumer audit. Stage 1 lint works with existing declarations. |
| `07d23db` | Defer performance bundle. Lazy scans merit a later pass; longer polls trade freshness for fewer probes, and permission caching needs its own review. |
| `d2ff745` | Defer automatic shell restart pending Nix/systemd lifecycle review. |
| `51850ce`, `b2ffd79`, `7564c3b` | Defer tooling/CI changes. Preserve local font-warning policy and deleted workflows. |
| `fd00ee8` | Exclude updater rollback; updater remains removed. |
| `2dcd6b4`, `27f0010`, `4356905`, `88b1ecd` | No documentation-only pick. Document actual imports without restoring deleted release docs/changelog. |

Unselected S5 portions include Cava wiring, palette/layout changes, notification
app-filter presentation, and media-card redesign. S6 excludes visualizer demand
and upstream night-light startup. S7 excludes updater/night-light changes.
S11 excludes settings-backup replacement and visualizer settings. Select source
tests by the behavior they verify; do not replace the complete fork probe file.
