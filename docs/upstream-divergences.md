# Upstream divergences

The standing differences between this fork and upstream, each with the
action an integration takes when they collide. Read this before importing
upstream changes; review affected entries afterward and retire anything the
integration made moot, inside the same commit. README.md owns the selection,
provenance, validation, and exceptional full-merge workflow; this file holds
the standing resolutions. The current rationale is recorded in
[ADR 0003](../adrs/0003-integrate-upstream-changes-selectively.md), which
retains the ledger protections introduced by ADR 0002.

## Default: the fork supersedes upstream

In any conflict, the fork's version wins; upstream's fixes come in where
they don't fight a fork redesign. One exception: when upstream ships its
own take on something the fork already built, stop and review it case by
case. Settle that decision before importing the conflicting implementation.

## Removed outright — keep deleted

The fork is distributed by nixos-config and never publishes releases or
installs by hand, so the release and distribution machinery is gone whole,
the manual installer with its uninstall, repair and bench tooling went
with it, and the package-updates/self-update stack went the same way
(upstream still ships and iterates all of it). Imports must preserve those
removals. The stacks' consumers are pruned wherever upstream grows new
ones: Hooks.qml carries no "update-available" event, probe-logic has no
updater suite and no repair-outcome check, SystemTools has no packageFamily
and no repairMatugen, the Maintenance section offers no Matugen repair (the
deployment wires Matugen to the wallpaper command, so a missing palette is
fixed by setting a wallpaper), DateTime has no agoText, and the EntryList
control only the updates section used is gone. Resolve delete/modify conflicts under
these paths as ours, re-delete anything a merge brings back under them,
and re-prune any new consumer a merge wires up:

<!-- keep-deleted:begin -->
packaging/aur
security/update-signers
scripts/release-notes.sh
scripts/silere-update.service
scripts/silere-update.timer
scripts/update.sh
docs/releasing.md
docs/releases
docs/install.md
docs/performance.md
docs/perf-history.md
docs/scripting.md
docs/troubleshooting.md
.github
CHANGELOG.md
CONTRIBUTING.md
modules/bar/widgets/ShellUpdateWidget.qml
modules/bar/widgets/UpdatesWidget.qml
modules/menu/controls/UpdateStatusCard.qml
modules/menu/settings/SettingsUpdatesSection.qml
modules/menu/controls/EntryList.qml
services/ShellUpdate.qml
services/Updates.qml
modules/bar/widgets/MediaVisualizer.qml
release.json
scripts/silere
scripts/doctor.sh
scripts/test-update.sh
scripts/install.sh
scripts/uninstall.sh
scripts/repair.sh
scripts/bench.sh
scripts/lib/ui.sh
<!-- keep-deleted:end -->

ci-lint enforces the list: a path here that exists again fails the gate,
so resurrecting one on purpose means removing its line in the same commit.
`.github` covers the Actions, Dependabot, and the issue and pull request
templates together: the gates run locally only, and the fork takes no
outside issues or pull requests.

## Shared files — union, with contracts

- `config/GeneratedDefaults.qml`: take upstream's defaults wholesale, then
  re-append the fork's added keys. The settings contract (AGENTS.md) must
  hold after the merge, and key-set changes tie the merge to nixos-config
  per README.md's coupling rule.
- `services/ShellSettings.qml`: fork-added properties and `_schema` rows
  merge as a union with upstream's. `barCenterInGap` defaults to `true`
  against upstream's `false`; keep the fork's default on any collision.
  `mediaRemoteArt` reads its initial value from `GeneratedDefaults`, whose
  checked-in copy carries upstream's `false`. Nix may declare `true`,
  accepting the OpenSSL crash risk `Media.artSource` documents. On a collision
  keep the binding, and carry any new upstream literal into
  `GeneratedDefaults.qml`.
- `modules/menu/settings/SettingsInterfaceSection.qml`: the Font row's
  shortlist is built by `_fontChoices`, which the lock screen's Font row
  shares, where upstream builds it inline in the row's `model`. Port upstream
  edits to that inline block into the function and keep both rows calling it.
- `services/ConfigStore.qml`, `config/PersistedFile.qml` and
  `services/ShellSettings.qml`: `ConfigStore.readOnly`
  (`SILERE_SETTINGS_READ_ONLY=1`, set by the lock process) gates every
  disk write of the settings layer: `ConfigStore.ensureDirectory`,
  `hardenFile` and `pruneBackups`, `PersistedFile.flush`, and
  `ShellSettings._backupSettingsText`, which returns true so a migration
  carries on in memory. Re-apply the gate to any writer an import adds to
  those files, or the lock rewrites the user's settings.
- `config/Settings.qml` and `modules/menu/settings/SettingsMaintenanceSection.qml`:
  `Settings.lockCommand` runs `ShellSettings.lockCommand` as `["sh", "-c", ...]`
  when it is non-empty, ahead of upstream's hyprlock-then-`loginctl` chain,
  which stays as the empty-string fallback. The Maintenance "Screen lock" row
  is hidden while that string is set, since the packaged locker does not need
  hyprlock. Keep both on an import of either file; `commandAvailable` needs no
  change because `sh` is always available.
- `scripts/ci-lint.sh`, `scripts/check-connections.py`,
  `scripts/test-qml-headless.sh` and `scripts/lib/qml-modules.sh`: the lock
  process's entry point, `lock.qml`, sits beside `shell.qml`, so every path
  list that names `shell.qml` names `lock.qml` too, and the animation-driver
  rule checks both entry points. The boot-arming rule stays on `shell.qml`
  alone, since the lock must not start the shell's armed watchers.
  `Quickshell.Services.Pam` is a required module for the lock's PAM. Add
  `lock.qml` to any list an import adds or rewrites, or the gates skip it.
- `modules/common/OutlineBorder.qml`: `_dpr` falls back to the plain Qt
  window's `devicePixelRatio` (`Window.window`) when `QsWindow.window` is null,
  as it is on a session-lock surface; desktop surfaces still read the QsWindow.
  Keep the fallback on an import of the stroke snapping.
- `qmldir` files, `BarContent`'s widget registry, `barWidgetMeta`, and the
  zone-order defaults: unions — keep both sides' entries.
- `scripts/check.sh` keeps sequential smoke cases and their shared launcher.
  The startup case uses a private configuration copy. Dereference source
  symlinks and fail the check if copying fails; never silently substitute an
  incomplete copy for the real settings. This isolates shell-owned configuration
  writes, not arbitrary configured commands or desktop services. Every smoke
  shell also gets a private cache directory beside that configuration, unmapped
  bars and a private session bus, so it neither fills the user's QML cache,
  reserves screen space on the live display, nor can claim the desktop's
  notification or tray names should their owner drop out mid-run.
  Every probe runner shares that private bus, and the layer-shell construction
  checks keep the Wayland runtime directory beside it. Probe windows
  stay off the live display, through the offscreen platform or `visible:
  false`, except the notification-stack and bar-hint probes, which map real
  layer surfaces to measure motion; each probe is stopped as the process
  group it was started in (next entry).
  The whole run holds idle off through `systemd-inhibit`, since the fork's
  notification-stack probe draws on the live compositor and a session that
  idle-locks mid-run stops giving it frames. Keep the re-exec at the top when
  an import rewrites the script's preamble; a host without logind access runs
  unguarded, and the stack runner fails by name while this user's hyprlock
  is running.
- `modules/menu/controls/SliderTrack.qml`: `_posToVal` returns `max` and
  `min` themselves at the ends of the rail, past upstream's off-grid bounds
  fix, because min + 1 × (max − min) can carry a float residue that the snap
  rounds a whole step down. Keep that on an import of the rail code.
- `services/Media.qml`: `_trackActivity` runs at startup as well as on
  playing changes, and ranks only listed players, past upstream's change
  handler, so players already playing when the shell starts are not ranked as
  new beside the next one to start. Keep both on an import of the player
  pick.
- `services/CpuTemp.qml`: `_sample` keeps a running average of the reads
  (`_settleWeight`) where upstream keeps the last read. The package sensor
  reports its hottest core at the instant of the poll, so a lone boost burst
  lit the TEMP chip and the alerts with a value the chip never held. Keep the
  average on an import of the sampler.
- `services/Notifications.qml`: `_prependHistory` orders by arrival as
  upstream does, but stops at rows dated after the current time, so rows from
  a clock that went back neither bury nor trim a new arrival. Keep the stop
  on an import of the history insert.
- `services/Network.qml`: upstream's rescan fallback, `_acceptWifiLink`,
  stays out while `_wifiNameWasLinked`: a network of the target's name already
  linked when the connect began proves nothing about the new link. Keep the
  flag on an import of the Wi-Fi connect.
- `services/Network.qml`: `refreshVpnAddress` and the address reader's
  staleness check find the tunnel through `_activeVpnUuid()`, which reads
  `_vpnState.active`, not upstream's `hasVpn`. The handler on `_vpnState` can
  run before the `hasVpn` binding catches up, so a tunnel coming up asked for
  no address until the next poll or menu open. Keep the direct read on an
  import of the VPN address.
- `services/Network.qml`: the interface watcher also rechecks the VPN when an
  interface's receive counter goes backwards, since a tunnel rebuilt under the
  same name between two reads (a Proton server switch on `proton0`) leaves
  upstream's name list unchanged. A rebuild the counter check sees also marks
  the address stale, so the next listings reread it even when the uuid and
  name stayed the same. Keep both on an import of the interface watch or the
  VPN reader.
- `services/Network.qml`: the VPN reader retries a missing address only after
  a listing that succeeded while detection is wanted. Upstream retries after
  any exit, so going idle, which kills the listing, spawns nmcli on an idle
  screen. Keep the gate on an import of the VPN reader.
- `modules/menu/HomePage.qml`: the VPN row sits in a `CollapsibleSection`, so
  it grows and collapses with the tunnel where upstream's row pops, and it
  reads "Disconnected" on the way out. The Connectivity label and card follow
  `_vpnShown`, which holds them up through that collapse by the section's
  height, where upstream gates them on `Network.hasVpn`. Keep both on an
  import of the VPN row.
- `services/OsdBarState.qml`: the full-charge alert keeps a latch of its own
  in place of upstream's charge cycle in `Battery.qml` (`chargeComplete`,
  `chargeRevision`). The first reading is a quiet baseline, taken when the
  OSD is built if UPower has already answered, and leaving AC or falling
  below 97 % re-arms it. The latch's Battery connection stays live
  while the session is idle or the OSD is off, and the alert checks the
  presentation gate before it latches, so a charge that ends and starts again
  out of sight is still announced on wake. The alert formats `Battery.pct`,
  not `Battery.label`, whose binding can lag the full edge. Keep all of it on
  an import of the battery alerts or the charge cycle.
- `config/Motion.qml` and `config/Disclosure.qml`: a `Disclosure` with
  `list: true` runs on `Motion.listOpen`/`listClose` and the standard curves
  in place of upstream's medium/fast emphasized pair,
  which snapped short lists open, and the list's contents fade over the
  same two durations so it never closes empty. `CollapsibleSection` forwards `list`;
  `SelectRow`, `InlinePicker` and `LevelRow`, the option list under
  `VolumeRow`/`BrightnessRow`, set it, and the chevrons that open them (`SelectRow`, `QuickSlider`,
  `ControlRow`) rotate through `Disclosure on rotation { list: true }`. Keep
  the flag and its sites on an import of any of these.
- `services/Audio.qml`, `services/SystemTools.qml` and `shell.qml`:
  `setSourceVolume` writes every mic level through
  `wpctl set-volume` (under `LC_ALL=C`, one run at a time a frame apart, the
  queued level tied to its mic serial) and `sourceVolume` shows the asked-for level
  until PipeWire reports it. Quickshell 0.3.1 skips a device-route write whose
  route reports no volume step (a Bluetooth headset's call-mode mic) while
  keeping the value, so the slider snapped back on the next route update. The
  in-process path stays for a system without wpctl. `SystemTools` scans
  `wpctl` and `pw-dump`, and `shell.qml` arms `AudioMode` at start. Keep all of
  it on an import of the mic path, the tool scan or the startup arming.
- `services/Audio.qml`, `services/OsdBarState.qml` and
  `modules/menu/VolumeRow.qml`: Bluetooth profile switches hold one shared
  presentation snapshot in Audio, so Sound, Home, the bar and OSD show the same
  readiness, name, volume and mute state. Audio queues user edits, guards device
  selection, and keeps live node readiness and microphone privacy separate.
  `AudioMode` releases the hold after observing another default device followed
  by a ready replacement serial on the requested headset/profile and a successful
  command exit. A two-second backstop covers missing transitions. Input edits
  replay only onto the original mic serial. The OSD ignores backend reconciliation
  signals during the hold, and Home closes its live-node picker. Keep this contract
  on an import of the audio service, OSD or volume row.
- `modules/menu/controls/RowDividers.qml`, `SelectRow.qml` and
  `InlineOptionRow.qml`: a line beside an open dropdown option's band fades
  the way it does beside a hovered card row. `RowDividers` reads an optional
  `rowBottomEngaged` for the line under a row, `SelectRow` raises it while its
  open, non-scrolling list ends on a band and fades its list hairline when the
  first option shows one, and `InlineOptionRow` reports that as
  `fillShowing`. Keep all three on an import of the dividers or the dropdown.
- `services/OsdBarState.qml`: `show` also drops volume while the fork's
  Sound settings page is showing (`MenuState.soundSectionActive`), since
  that page carries its own volume slider, as the home page does in
  upstream's gate. Keep the check on an import of the OSD gate.
- `services/CalendarState.qml`: `weekendFor` copies the working days with
  `Array.from`, because `Locale.weekDays` is a sequence that upstream's
  `Array.isArray` gate rejects, so every locale fell back to Saturday and
  Sunday. Keep the copy on an import of the calendar weekend.
- `scripts/probe-lib.sh` and the `scripts/test-*.sh` runners: every probe
  starts under `setsid` and `_probe_stop` ends its whole process group, since
  a probe's helpers such as fontconfig's `fc-list` outlive a single-pid stop
  and race the runner's cleanup. Upstream stops the one pid; whether its lazy
  font scan keeps `fc-list` out of its probes is unverified. On a collision
  keep the group stop and its guards: a live pid is only signalled when the
  calling shell started it, its group only when it leads it, a reaped
  leader's lingering group is the one exception the code justifies, and a
  malformed pid never reaches `kill`. A runner's private bus comes from
  `_probe_private_bus`, which supervises `dbus-run-session` instead of
  exec'ing it, since that tool passes no signal on to the runner it starts.

## Feature collisions — standing resolutions

- Failed capability scans retain the last coherent result without advancing
  `SystemTools.scanRevision`; that revision tracks changes to capabilities.
  Hook recovery retains process-group cleanup and bounded execution.
- `BoundedProcess` and `SupervisedProcess` clear `_exitSeen` when a run
  starts, not only when one stops, so a command chained from `exited` still
  reports its own failed start. Keep that line when an import rewrites them.
- Wi-Fi forgetting uses the shared confirmation state and service-side
  saved/active guards. Capture row identity before disarming confirmation,
  which can synchronously replace the row model.
- Bluetooth forgetting uses the same confirmation and identity rules, plus
  paired/connected guards. Hard-block state disables the fork radio controls;
  active pairing may extend the 20-second guard at most eight times, and a
  device still reporting Connecting at most twice. Each new attempt resets that
  budget. A completed pairing marks the device trusted and then connects it.
  Retain the fork's 60-second adapter pairable timeout and restore only
  pairable state owned by this service.
- Shared fullscreen tracking retains the compositor boundary and only
  notification-silence or integrated-OSD demand. Keep removed visualizer
  demand out of `FullscreenState`. The Hyprland backend reads the window's
  fullscreen mode as a bitmask: bit 2 is real fullscreen, while mode 1 alone is
  a maximized window.
- Calendar marks remain write-protected until their initial load succeeds or
  reports a missing file. Corrupt, unreadable, and newer-format files remain
  protected after loading; an early click does not replay over restored marks.
- The calendar reads today from a fresh `new Date()`, not upstream's
  `DateTime.currentDate`: `SystemClock.date` holds its last tick's wall time, so
  it stays stale after a timezone change until the next tick. Do not import
  `currentDate`. The week-number column is wider than upstream's so a
  two-digit label keeps clear air before its hairline, that hairline is
  inset to the day markers' extent instead of running the full grid height, and
  the day grid starts a gutter right of the hairline so the today marker does
  not graze it; keep the fork's `weekCol`, `weekGap`, and the inset. The
  today and hover marker is a rounded square at `Theme.radiusField`, not
  upstream's circle, to match the today pill and month button above it; keep
  the fork's `marker`. The month label is centred between its arrows, without
  upstream's offset toward the day grid; do not take that offset back. The
  card keeps a 20px `pad` on every side, wider than upstream's 14, so the
  header and the outer columns sit the same distance from the edge. Calendar
  week start and week numbers are otherwise upstream's.
- Bar hover tooltips remain enabled and configurable. Keep `BarHintState`,
  `BarHintPopup`, the popup host, and every widget's hint bindings together.
  The retained popup must also take compatible upstream idle-settle fixes,
  including cancellation of its pending startup frame.
- Glass thickness is adaptive: `GlassSample` reads the wallpaper sample the
  deployment's wallpaper command writes to `~/.config/silere-shell/glass.json`,
  and `Theme` derives `panelOpacity`, `popupOpacity`, `_glassTint` and
  `_barTint` from it under the `glassAdaptive` key (ADR 0004). Upstream paints
  fixed alphas. Keep the sample-driven derivations, the key, and
  `ColorFade`'s second gate on `GlassSample.transitioning` when an import
  touches Theme's glass tokens or the leaf-fade gate.
- Palette changes keep the fork's central `MatugenTheme` transition and its
  leaf-fade gate. Do not introduce upstream's parallel `PaletteFade` mechanism
  or replace the fork's glass and control tokens with upstream's palette.
- Blur stays with the deploying Hyprland config's `silere-*` layer rule. Do
  not import upstream's `BackgroundEffect.blurRegion` protocol blur
  (`995f262`, `d13d351`, `5aca380`, `b21d987`) or the region hunks later
  commits carry, such as `FloatingPopupCard.blurItem` and the OSD's blur
  shapes. Once a surface creates a background effect, Hyprland lets its
  region replace the layer rule, so one imported region takes that surface
  off the rule and it loses blur on every frame upstream clears the region,
  such as while it moves or fades. A popup window split can still be
  considered on its own; it keeps the layer rule.
- Sound keeps the fork's audio service, sound settings, privacy widget, and
  `audio` IPC contract. Do not add a second microphone widget or replace its
  controls with `PwVolumeControl`; compatible device and lifecycle fixes can
  be adapted without changing those interfaces.
- Dynamic workspaces keep the fork's occupied-workspace list and trailing
  empty workspace, up to workspace ID 15. Dynamic bar scrolling wraps within
  IDs 1–15 in both directions and skips IDs owned by another output. Bound
  enumeration before building the delegate model, including when external
  compositor shortcuts select higher IDs. Those shortcuts remain compositor-owned.
  Upstream's slot/app-model extraction must not replace
  those semantics or its marker behavior as a side effect of an import.
  Shared bump helpers may replace the matching gestures while retaining the
  fork's separate workspace entry animation; do not add upstream's slot-swap
  fade as part of that consolidation.
  Bump retriggering preserves the current value. Keep gate cleanup explicit
  through `retire()`; upstream's reset-on-stop handler causes a jump during
  rapid marker retriggering because `restart()` first stops the animation.
  Menu access must remain available when compositor workspace data is not
  ready, without requesting workspace activation or a marker pulse.
- Night light keeps the systemd service backend, so upstream's restore of a
  hand-chosen state after a shell restart (`nightLightOn`) stays out: the unit
  outlives the shell. Its solar math follows upstream's. The lock action keeps
  its existing provider selection. Additional upstream provider settings
  require a separate decision with their backend and UI consumers.
- The floating OSD keeps its height and slide transitions. Shared bump
  consolidation applies to the bar OSD's existing nudge without adding
  upstream's floating OSD bump to the fork.
- Settings keep backups before reset and migration, backup permission
  hardening, locked widget-order scrubbing, and future-version preservation.
  Ordered migrations may replace legacy transforms without removing those
  protections; migration output is written only after successful loading and
  backup. A failed migration backup blocks all settings writes, including
  queued edits and reload teardown, while that legacy source remains loaded.
  Retrying identical backup text must reach disk; an external replacement
  invalidates the previous save cache and follows the normal load policy.
- Menu pages restore retention for the active tab whenever the menu reopens.
  A hover-warmed window can survive its close grace after releasing that page;
  reopening the same tab must rebuild it even when the tab id has not changed.
- Notifications keep the fork's `ExpandableBody` interaction and the popup
  layer's constant screen-sized height. Take upstream delivery features such
  as grouping, inline replies, batch retirement, and sender-image hardening
  around those two constraints. Stack displacement animates a separate visual
  position with an explicitly controlled NumberAnimation and a Translate.
  The Column bypasses a child's Behavior on y, while its move transition
  restarts during animated height changes and cannot be interrupted by its
  enabled gate. Keep the Column's layout position authoritative. Stop visual
  movement and follow layout while any loaded card animates its height or
  dismissal collapse, or shared idle/reduced-motion policy disables motion.
  Arm movement after positioning completes; new and returning hidden cards
  must snap to their first position. Keep viewport and scroll content bounds
  large enough for moving cards, within the existing screen-height cap.
  Defer the Repeater-count reveal-all reset until the model update completes,
  then recheck the current count and cap. The service count can change earlier
  and briefly hide a retained visible card before it reindexes.
  The history page's stacked runs are the
  fork's own: an upstream history grouping lands under that fold or not at all.
  Popup and history dismiss icons center their measured ink horizontally,
  with fractional positioning retained for fonts such as Berkeley Mono.
  Expansion belongs to a run's retained oldest entry, including its timestamp,
  rather than its ordinal among the day's runs. Removing an older run must not
  transfer expansion to another run. A run joined by clearing the row between
  two runs of one app keeps its oldest entry's state when that was open; otherwise
  it opens when the upper run was open or neither side was tall enough to stack,
  and a standing stack takes a short side in.
  An older row that history files below an open run's tail becomes its oldest
  entry, and `HistoryGrouping` carries the open state to it. Clearing that
  oldest entry hands the state to the row above it when that row stays in the run.
  The fork's duration-picker DND replaces
  upstream's scheduled quiet hours; keep `dndSchedule`, `dndFrom`, `dndTo`,
  their settings rows, and their service logic removed. The `quickActions dnd`
  IPC toggle goes through that picker's `toggleDnd`, so turning DND on arms a
  timed run from the saved duration; do not route it to upstream's quiet-hours
  path or a plain `dnd` flip. Notification history
  retains `sessionCurrent` through `PersistentProperties`, which survives QML
  reloads but not process exits. Restore on its `loaded` signal, before the
  server re-emits kept notifications; defer pruning until those arrivals have
  rebuilt the live list, including cleanup triggered by settings changes.
  Until settings are ready, restore and trim against the schema maximum;
  apply the configured limit and retention only after the settings read.
  Disk history uses `ConfigStore.notificationsPath` and `PersistedFile`.
  Rows restored from disk have `sessionCurrent: false`; reload restoration
  retains current-session identity. A reused server ID must not inherit an
  earlier process's read state or target its live notification through an
  archived row. Preserve unreadable and corrupt files, including a
  supported-version file whose `history` is not a list. Upstream resets the
  write permission on every read; the fork restores `notifications.json` once
  per engine and every exit from that restore sets the permission, so that
  per-read reset is not ported. Keep that restore the only place history is
  restored; `onLoadFailed` is the only other setter of the permission. For
  newer-format files,
  restore compatible history/state into memory while leaving the file untouched;
  writes stay blocked, including after in-memory edits or persistence changes.
  Disabling persistence clears existing history and queues an empty disk
  archive; later arrivals remain in memory until reload or process exit.
  Nix supplies the initial value, which saved UI settings may override.
  The storage path is `silere-shell/notifications.json`; keep unrelated
  hardening for `quickshell/states.json` removed. Source selections and
  acceptance checks live in [the integration plan](upstream-picks-2026-09-16.md).
- Notification icon files resolve against `IconResolver._systemIconRoots()`,
  which adds `XDG_DATA_DIRS` entries, `/run/current-system/sw/share`,
  `~/.nix-profile/share` and the per-user profile to upstream's FHS roots; the
  deploy machine has no `/usr/share`. On a collision keep the union and
  upstream's traversal, `file:` authority and length checks. These roots are
  trusted like the user's own files, as SECURITY.md states.
- The Bluetooth bar widget stays an actionable `StatusActionPill` that opens
  the configured manager. Take compatible upstream service, accessibility,
  hint, and lifecycle improvements without replacing it with a passive pill.
  Details selection clears on the device's connection event; clearing it from
  the derived expanded-state handler creates a binding loop on disconnect.
- Power profiles keep the command backend and its `asusctl` fallback. Take
  backend-neutral upstream fixes, but do not replace this with a UPower-only
  implementation because the deploying machine runs `asusd`.
  Refresh an empty profile list when a panel opens; a successful current-profile
  read must not leave the System page's choices empty after a missed startup list.
- The fork's media card lives at `modules/menu/controls/MediaCard.qml` and its
  redesign wins. Never restore the obsolete `modules/menu/MediaCard.qml` path;
  port compatible upstream privacy and metadata fixes into the controls file.
  Only an open media host may advance the shared artwork candidate after a
  load failure; a closed card retained during its exit must not change it.
- The bar media widget opens that card on click and focuses the player on
  right-click; its accessible press action and name follow the click. Keep
  upstream's play/pause click and press action, middle-click focus, and
  wheel-to-skip out of it.
- The bar clock keeps text-only hover feedback, with no hover, pressed, or
  calendar-open background. Drop any highlight cap or `_calendarOpen` fill
  an import brings back.
- `RowDividers` fades the lines either side of a hovered or pressed row, so
  the edge-to-edge `RowHoverBg` fill reads as one band. Keep the fade on a
  collision, along with the `row*` hover contract it reads from `SelectRow`
  and the `VolumeRow`/`BrightnessRow` wrappers.
- The Cava audio visualizer stays removed, including its bar placements, process
  and profile management, settings, fullscreen demand, and underline glow.
  Compatible media fixes must preserve playback controls and track progress
  without restoring the visualizer or its tool dependency.
- Tray context menus keep adaptive lane-fit placement, drill-in navigation,
  and root-lane overlays so nested menus fit without overlapping their ancestors.
  Apply hover/lifecycle fixes around that geometry; upstream's simpler
  `Metrics.flyoutX` placement is not a replacement for it. Checkbox entries
  draw an outlined box that fills with the accent; keep it over upstream's
  bare check mark, which leaves an unchecked row looking stray-indented.
- Control popups keep one exclusive `OverlayCoordinator` claim: menu,
  calendar, tray menu/list, quick actions, keybinds, wallpapers, media, and
  the power countdown all close their peers and reject late opens while idle
  or in overview. All nine states inherit `PopupState`, directly or through
  `AnchoredPopupState`, and register with the coordinator. Represent the
  popup-sourced tray menu's parent with `popupParent`; keep centered pickers
  free of anchor machinery. Media and tray-list anchor loss closes
  immediately; the other anchored states retain 150 ms replacement recovery.
  Registry metadata preserves the existing control-surface/bar-hint sets and
  `ControlSurfaces.opened` refresh signal. Panels, menus, centered pickers,
  and tooltips share `PopupAnimation` for the menu's fade and short vertical
  slide. Centered pickers use `FloatingPopupCard` with centered placement.
  Keep scaling removed from these surfaces. Resolve the bar edge and initial
  content size before the entrance; calendar month resizing only animates once
  the card is fully shown, as a `MotionBehavior` on the grid wrap's height, so
  upstream's `SmoothGlide` card height (`91ad70c`) stays out.
- Behavior timings branch on the Behavior's `targetValue`, and `Disclosure`
  takes a `closedValue`. The fork keeps press and hover scale Behaviors inline
  instead of upstream's `PixelScale`; port fixes aimed at `PixelScale` into
  those inline Behaviors. The menu panel's geometry (width, rail, settings-nav
  slide, power drawer, height) runs on `Motion.standard` over the single
  `Motion.menuResize`, in both directions, not upstream's emphasized pair over
  `panelResize` and `panelCollapse` with a `>= panel.width` branch, which
  front-loads half the distance into one frame and reads as a snap. The height
  is a `NumberAnimation` on the same curve and length, starting on the same
  frame as the width, not a `SmoothedAnimation` of its own, so upstream's
  `Motion.panelVelocity` stays deleted with it. One length keeps
  every edge landing together; keep the token, the curve and the single clock
  when an import touches those Behaviors. The height Behavior is armed only
  for changes that step (tab switches, section swaps, nav group toggles); a
  select dropdown or collapsible already animates its own height, and arming
  the Behavior for it makes the panel trail the content.
- `Motion.pageIn` no longer promises to outlast the panel's resize. Upstream
  defines it as `panelResize` so content never lands opaque inside a
  still-resizing panel, but the menu panel now resizes over `menuResize`, so
  `SettingsPage._sectionEnterDefer` waits that length itself. Keep the wait on
  `menuResize` and `pageIn` unlinked from it when an import touches either.
- Menu pages fade through on a tab swap: the leaving page exits over
  `Motion.pageSwapOut`, and the arriving page holds back for it (`swapWait`,
  measured by `MenuWindow._beginTabSwap` from the pages actually on screen)
  before entering over `pageSwapIn`. Upstream's `PageShell` starts both at once,
  so the two pages sit on top of each other at partial opacity. Keep the wait
  and the two tokens, plus `Motion.frameAllowance`, the measurement slack that
  reduce-motion deliberately does not scale, when an import touches
  `PageShell` or the page Loaders.
- The notifications page stays built for as long as the menu is open
  (`MenuPageLifecycle`), not only while its tab shows, and `PageShell` starts
  at zero opacity. Upstream builds the page on the tab change and releases it
  after the exit; its loader builds in the background, which gets about a
  millisecond a frame at a high refresh rate, so every visit sat behind the
  loading overlay while the part-built page drew through it. Keep both when
  an import touches the page retention or `PageShell`.
- History rows leave on their own clock (`ListView.delayRemove` from
  `RecentPage`'s `_noteLeaving`), not through a remove transition: Qt drops a
  running remove transition on any later layout of the list, so a second
  clear, a history trim, or a run folding as it merges cut the first row's exit
  short. A leaving row keeps its place until it has closed, so the list lays
  out from live heights on every frame: the rows below close up, a list at its
  end follows the row down, and removals animate other rows' heights (they no
  longer raise `_settling`; inserts still do). The list never repositions a
  row it has let go of, so each leaving row follows the row above it
  (`_leavingRows`, `_after`). A jump past a page hands every built row back to
  the pool, leaving ones included, and Qt never resets `delayRemove`, so
  `onPooled` stops the row's close and clears the flag; otherwise the close
  shuts whichever entry the row is reused for. Upstream has no remove
  transition here. Keep the row-owned exit when an import touches the history
  list, its transitions, or the delegate's height.
- Removing the first history row under a day hands its header to the next
  row of that day (the delegate's `_handoff`, `_handedTo`, `_headerFrom`):
  the next row takes the header over at once and draws it where the first
  leaving row drew it, however many rows are still closing above it, while
  its card rises into the header's room as they close. Each handoff rides on
  its leaving row, so clears under two days run side by side.
  The leaving row fades `_leaveFade`, not its opacity, and hides its own
  header. Upstream fades the whole row while the next one draws a second
  header and slides it up. Keep the handoff when an import touches the
  history delegate or its transitions.
- Menu pages are laid out at the destination geometry, not at the live width:
  `MenuWindow.contentPad` and `innerW` key on `panelW` (`contentW` stays live
  only as the clip box), and a page on its way out keeps its own geometry in a
  per-page `PagePin` until it has faded; a page called back mid-fade under a
  pin that no longer matches its resting geometry finishes its exit under the
  pin and enters fresh instead of resuming. `PageShell` drops its 10 px slide
  (`slideOnSwap`) while the panel width is changing, and every tab change
  closes the power drawer from `tabChanging`, so the width it predicts is the
  width it gets. Upstream sizes pages from the live width, which reflows text
  every frame of a resize; keep the target layout, the pins and
  `_widthFor` as the single width decision when an import touches the pane.
- `ActionButton` has no hover lift: its surface moves only on press, and hover
  is the fill alone. At a fractional output scale the 1px lift lands between
  device pixels and resamples the label, which reads as the button shifting.
  Keep the lift out when an import touches the button's motion.
- `ActionButton` and `IconButton` are thin surfaces over `ButtonBase`, which
  holds the activation gate, hover and press state, the accessible role and
  the disabled fade. An import that changes that shell in either button ports
  into the base; one that changes a button's surface or content lands in the
  thin file.
- `VolumeRow` and `BrightnessRow` are thin derivations of `LevelRow`, which
  owns the slider, the collapsible option list and the row-hover forwards;
  each row supplies only its service bindings and `optionGlyph`. Port an
  import of the shared wrapper into `LevelRow` and one of a row's bindings
  into that row. `ChoiceChipRow`, `SliderRow`, `SwatchPickerRow` and
  `DescribedChipRow` lead with `RowGlyph`, the 18px icon cell; an import of
  that cell ports there.
- `Theme.barHoverCap` and `Theme.barPressCap` name the capsule behind a bar
  widget, read by `Pill` and the tray's per-icon caps. Keep the tokens and
  their two readers on an import of either hover treatment.
- `services/Network.qml`: `_splitNmcliLine` is also the terse-output parser
  for the fork's `WifiProfile`, which carries no copy of its own. An import
  that renames, moves or inlines the splitter keeps a callable of that name
  on `Network`, or repoints WifiProfile's three call sites in the same commit.
- Every full-screen popup but the tray menu derives from
  `modules/common/OverlayPopupWindow.qml`: the layer-shell setup, the
  workspace-switch close, the Escape shortcut, the outside-tap dismiss with
  its guard, the mask and the shadow live there, and each popup declares its
  `targetScreen`, state, `silere-*` namespace and card, overriding
  `handleEscape()` when Escape first backs out of something inside the card.
  Upstream moved the same popups onto its two-window `FittedPopupWindow`,
  which the fork declined. An upstream change to a popup's window code ports
  into the base; a change to its card lands in the popup's file.
  `TrayMenuPopup` keeps its own window because its outside tap must spare an
  open flyout and may also close the tray list.
- `ConfirmButton` paints its rest, hover, press and armed fills with
  `Theme.controlFill`, not upstream's mix into `Theme.menuControl`. Under
  glass `menuControl` is a text-coloured wash, and a mix into it drops the
  alpha that kept it dark, so the button turns into a bright block with an
  unreadable label. Rest also uses the opaque control base so the hover fade
  cannot flash bright while interpolating from a pale translucent wash to a
  dark solid. Keep `controlFill` when an import touches its colours.
- `ConfirmButton` places its glyph so the glyph's ink centers on the label's
  capitals, 6px from the label, where upstream centers the two line boxes 4px
  apart. The symbols fallback gives the glyph a taller line with a lower
  baseline, so centered boxes leave the icon about 2px low. The ink is measured
  at 100px, since whole-pixel rounding at caption size is as large as the
  correction, and the glyph takes an unrounded y from where the label sits.
  Keep that placement when an import touches the button's row.
- Hyprland Log out, Reboot and Power off run `scripts/hypr-session-end.sh`
  (`HyprDispatch.sessionEndCommand`), not upstream's inline `sh -c` in
  `HyprDispatch.exitCommand()`, and Settings wraps the reboot and power-off
  commands in it on Hyprland. hyprshutdown kills every layer client, this
  shell included, so it must run in its own transient systemd unit; started
  from the shell's service it dies with that unit. It runs with `--no-exit`
  and the script ends the session itself once hyprshutdown's apps are gone.
  Cancel is read from exit status 2, which nixos-config patches into
  hyprshutdown; stock hyprshutdown exits 0 for it too, so the script falls back
  on its `--verbose` log. Recheck the patch and those log lines when
  hyprshutdown is upgraded.
  Keep the unit, the restart of the session units it stopped, and the failure
  notification. Port upstream's hyprshutdown flag or fallback changes into the
  script. The countdown's actions start from the shell's service
  (`runOrNotify`'s `inService`), not through upstream's `Compositor.launch`:
  the script learns which unit to restart from its own cgroup, and a process
  the compositor starts belongs to no unit. The lock screen and other
  launches keep upstream's compositor path.
- Log out, Reboot and Power off open the fork's countdown card
  (`PowerActionState`, `modules/power`) instead of upstream's
  arm-and-press-again rows; every power action in the shell runs through
  `PowerActionState.run`, which keeps the sandbox guard. The lock process is
  the exception: its card (`modules/lock/LockPower.qml`) counts down on its
  own, reuses only `PowerCountdownBody`, and runs plain `systemctl suspend`,
  `reboot` or `poweroff` in a `Process`, never `Settings.rebootCommand` or
  `poweroffCommand`, since hyprshutdown would let an app's save prompt hold
  the shutdown behind the lock. Outside a wrapper-started lock it runs a
  stand-in instead. Do not route it through `PowerActionState` or the
  session-end script on an import of either. The `power` IPC
  target exposes `request logout|reboot|poweroff` and `close` for launchers;
  requests require an available command and use the same countdown and
  idle/overview refusal as the rail, with no direct-execution fallback.
  Another accepted request replaces the action and restarts the countdown.
  Port upstream's rail changes around the rows' `onTriggered`, and do not
  restore their `confirm` or cross-disarm wiring. `PowerRailRow`'s
  arm-and-confirm code stays commented out in place, with `armed` a constant
  `false`; take upstream edits to it into the commented block rather than
  reviving it.

## What belongs here

An entry exists only where an upstream import could go wrong non-obviously: a
removal, a shared-file policy, or the feature-collision default above.
Fork-only features never get entries — new files don't conflict, and their
hooks into shared files are already covered by the union entries. A commit
that creates, changes, or moots a divergence updates this file in the same
commit; there are no batch cleanups.
