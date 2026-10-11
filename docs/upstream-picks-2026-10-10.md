# Selective upstream integration: the October 10 fixes

Status: implemented and gated; the live checks under
[Not yet verified live](#not-yet-verified-live) are pending. Base:
`3b287616bffabffba065c2f85ccea6797daa2da3`.

## Review range

The review covers the 83 upstream commits after
`1b20ece42dae1dc7693b16fe139732d224e720e9` through
`dab16d682b36959b251a13b58ca6d26a988dc620` on `upstream/main`, dated October 5 to 9 and spanning the 1.3.0
and 1.4.0 releases. Sources are from
<https://github.com/s3rven/silere-shell>. Several upstream commits bundle
unrelated work, so each fork commit takes only the hunks for one fix.

## Selected

| Commit | Subject | Upstream source |
| --- | --- | --- |
| `ac0eda9` | fix(slider): hold a slider's value when its handle is grabbed off centre | 2cbd7b1 |
| `2c6a138` | fix(pill): let a text swap finish under rapid text changes | 64b7f40 |
| `7783e75` | fix(calendar): ignore navigation while closing and settle on reduce motion | 91ad70c |
| `0b9d94c` | feat(calendar): label days and weekends by locale and scale the nav row | 91ad70c |
| `19107ff` | fix(notifications): keep action identifiers case-sensitive | 23928e6 |
| `a25c50a` | fix(notifications): keep non-expiring cards when the session goes idle | 23928e6 |
| `5760547` | fix(notifications): list history by arrival, not by close | 5dca77b |
| `febd7da` | fix(notifications): decode notification text once | 23928e6 |
| `4dc5de1` | fix(battery): drop the percentage scale guess quickshell 0.3.1 made dead | 8f115b6 |
| `ae2993f` | fix(osd): announce a full charge once per charge | 9d3b66a |
| `34c7c63` | fix(audio): guard the volume bindings on the audio object | c1ebbba |
| `dc2f67b` | fix(network): let a wifi connection finish when a rescan replaces its access point | 9d3b66a |
| `4242747` | fix(media): show the most recently active player | c7e0b9d |
| `b7d5898` | fix(lock): start the lock screen through the compositor | b86f1cf |
| `6e77c94` | fix(hyprland): refresh workspaces when a window names one the model lost | f1d0f53 |
| `dc22e35` | fix(hyprland): keep closed windows off the bar after a stale snapshot | 4541db8 |
| `61b7a7f` | fix(power): start the countdown's actions from the shell's service | follow-up to b86f1cf |
| `6ab33fd` | fix(media): rank players already playing when the shell starts | follow-up to c7e0b9d |
| `1b75cfc` | fix(notifications): keep a new arrival above history rows dated in the future | follow-up to 5dca77b |
| `8a69a51` | fix(network): settle a wifi connect from the live list only for a new link | follow-up to 9d3b66a |
| `32acbcc` | fix(calendar): read the locale's working days as an array | follow-up to 91ad70c |
| `3ce292e` | fix(osd): take the first battery reading as a quiet baseline | follow-up to 9d3b66a |
| `4b96d37` | perf(hyprland): filter closed windows by address, not the ipc snapshot | follow-up to 4541db8 |
| `bfb0438` | docs(history): say where an older arrival lands against the run tail | follow-up to 5dca77b |

## Material adaptations

- Lock: `SystemTools.runOrNotify` starts commands through
  `Compositor.launch`, so the lock screen, suspend and the sound mixer row
  run in Hyprland's session rather than in `silere-shell.service`, whose
  control-group kill took a menu-started hyprlock down with the shell. The
  countdown's Log out, Reboot and Power off stay in the service (`61b7a7f`,
  ledger), since `hypr-session-end.sh` restores the session from its unit.
  `HyprDispatch.launch` shells out to `hyprctl` instead of the in-process
  `Hyprland.dispatch`, because the socket write reports no refusal to fall
  back on. The fork has no `Audio.openSoundSettings`; its mixer row already
  uses `runOrNotify`. Compositor-launched commands get Hyprland's
  environment; every tool the lock and power paths call resolves on its
  `PATH`.
- Workspaces: the fork has no `_wsNumber`, so the missing-workspace check
  reads `c.workspace.id` inline and does not resolve the string addresses
  Hyprland 0.57 sends. The `changeworkspaceid` refresh is ported but cannot
  fire on 0.55.
- Notifications: the idle exit gates the fork's own handler on
  `_autoClose.shouldRun` instead of upstream's `_handleIdle`, keeping
  `cancelReply()` first and `_completeDismiss()` for a card already leaving.
  The arrival-ordered insert omits `historyRevision`. Text is decoded once at
  capture; rows restored from disk only lose control characters. Rows an
  older build saved may already have been decoded twice, which cannot be
  undone. The disk probe's recycled-id seed now arrives last, as it would.
- Battery: a direct pick, renamed to the fork's subject style; the fork
  keeps `Quickshell.Io` for its charge-limit probe. The full-charge alert
  takes a latch instead of upstream's charge-cycle state machine: it fires
  once per charge, re-arms off AC or below 97 %, and shows the reported
  percentage.
- Media: `pickPlayer` keeps the fork's playing, paused, stopped ranking and
  breaks ties by last activity; `cyclePlayer` and `preferredPlayer` stay.
- Slider: the grab centre comes from `_shownRatio`, where the handle is
  drawn, without device-pixel snapping; the ledger's `_posToVal` end clamp
  is unchanged.
- Calendar: everything except the `SmoothGlide` card height (ledger). With
  `en_US`, weekday headers read `SUN MON …` instead of `SU MO …`, and the nav
  row grows from 30 to 32 px.

## Declined, deferred and skipped

- Declined by the maintainer earlier and still declined: the protocol blur
  and every glass, blur-switch and translucent-surface follow-up
  (`d20fe26`, `c46f02c`, `24b0c15`, `fb1d0c2`, `e303e90`, `adf9aea`,
  `72cb273`, `a8f9a89`). `popupMatchBarOpacity` is off on this desktop.
- The fork has its own feature: Keep Awake (`0d78202`, `e0bc693`; the
  fork's Caffeine), the muted bell beside the clock (`adde9da`; the DND
  pill), the Now Playing page and its media hunks (`004a604`, `c5fcff2`,
  `f99e49d`, `739af9f`; the fork's media card keeps `cyclePlayer` and a
  512 px backdrop), the menu motion rework (`62c79cb`, `3b5cdd1`, most of
  `64b7f40`; the fork's single clock lays pages out at their destination),
  and the tray menu window (`54a3734`, `5ee633e`; the fork's lane fit
  already keeps a nested submenu off its ancestors).
- Removed from the fork: installer, AUR, updater, release and `doctor.sh`
  changes (`58ae412`, `c641d5a`, `d8e05f3`, `f637725`, `58b66d4`, release
  and README commits), and the `scripts/` to `dev/` move (`1355b62`).
- Deferred:
  - The shared fitted popup window (`10b88cb`) and the Hyprland focus grab
    built on it (`ac10bc5`, `a7a38e7`). About 1,900 changed lines against
    the fork's own `MenuWindow`; worth reconsidering only as a separate
    GPU-time decision, and the split keeps the layer rule.
  - Device-pixel snapping for toggles, sliders, swatches and badges
    (`8668094`, `87949c8`, `caa067c`, `5109858`, `7608665`). It needs
    `PixelSnap` from `af8cde3`, still deferred, and is worth taking only if
    a 1.6× eyeball shows soft edges.
  - Moving notification history to the state folder (`edfc411`,
    `6d0fcc7`). `~/.config/silere-shell` is not tracked by a dotfiles
    repository here, and the ledger fixes `ConfigStore.notificationsPath`.
  - Battery login baseline and charge-cycle state machine (`9d3b66a`); the
    fork takes only a full-charge latch.
  - The connectivity and sign-in warning (`0b89fe7`): NetworkManager
    connectivity checking is off on this machine.
- Not applicable with this configuration or already handled:
  - Floating bar side gaps and corners (`98906a6`, `116dfa9`, `2a881e6`,
    `90f9d87`): `Metrics.barSideGap` already shares the side gap with
    popups and fits the window gaps; the corner fix applies only with no
    edge gap and carries blur-region hunks.
  - Workspace icons, marker and underline polish (`1c32560`, `37ebad8`,
    `11ea599`, `8dd683f`, `3445578`, `145912e`): app icons, numbers, the
    underline glow and the bar shadow are off here, and the fork's marker
    and urgent check differ.
  - `5b03a24` names icon-less apps; correct but invisible while workspace
    icons are off.
  - Calendar height through `SmoothGlide` (`91ad70c`): the ledger owns
    calendar resizing.
  - The swatch ring in the swatch's own colour (`59cdba7`): the fork draws
    its own growing per-chip ring.
- Offered and not taken by the maintainer: reserving the floating bar's
  edge gap only on the screen side (`44ac61d`; the gap below the bar stays
  12 px against 8 px window gaps), keeping a muted output muted when
  scrolling down (`9d3b66a`).
- Candidates for a later review: the action-button wrap and empty-state
  wrap of `23928e6`, the Wi-Fi Out of range label and password draft of
  `9d3b66a`, slider availability of `9d3b66a`, the
  4.5:1 description contrast and `cancelFlick` of `64b7f40`, `7fbd96e`
  (disk usage without a shell), and the IPC-target lint of `f805457`.

## Validation

Each implementer's commits passed `bash scripts/ci-lint.sh` and
`bash scripts/test-logic.sh` in its own worktree. On the integrated branch,
`bash scripts/ci-lint.sh` passes and
`nix develop . --command bash scripts/check.sh` reports zero failures with the
four known environmental warnings; `PROBE-LOGIC` passes 573 checks, including
the ported and new cases. An earlier run failed only the notification-stack
probe, which refuses to run while the session is locked.

The lock launch was checked against the live Hyprland 0.55.4: the Lua
`hl.dsp.exec_cmd` form returns `ok`, an unknown call returns an error that
triggers the local fallback, and every tool the lock and power paths call
resolves on Hyprland's `PATH`. Nothing visible ran.

An adversarial review of the integrated branch found that routing every
`runOrNotify` command through the compositor left `hypr-session-end.sh`
without a unit to restore; a process Hyprland starts belongs to no unit
(`systemctl --user whoami` exits 1), which was reproduced. `61b7a7f` keeps the
countdown's actions in the shell's service. Three lower findings, which
upstream shares, are fixed as well:

- `6ab33fd`: players already playing at start were ranked in bus order beside
  the next one to start.
- `1b75cfc`: a history row dated in the future, from a clock corrected
  backwards, buried a new arrival and, with history full, trimmed it.
- `8a69a51`: with a network of the same name already linked, the rescan
  fallback could report a failed connect as a success.

The new history and Wi-Fi probe cases fail on the code before their fixes.
Two findings stay open:

- `Qt.locale().weekDays` is assumed to number Sunday 0, as upstream does;
  English locales are unaffected.
- The prev and next arrows take the disabled look while the calendar fades
  out, as upstream's do.

## QML review

The repository's `qt-qml-review` ran over the changed QML. Its linter's 11
hits on changed lines were false positives or the files' existing patterns,
and `qmllint` reported nothing on changed lines. All six review missions
returned. Fixed from them:

- `32acbcc`: `Locale.weekDays` is a sequence, so the `Array.isArray` gate
  upstream ported always fell back to Saturday and Sunday; reproduced with a
  headless `ar_SA` locale, and the probe now feeds a real locale.
- `3ce292e`: the full-charge latch stayed quiet at login only when UPower
  answered before the OSD armed; the first reading is now a silent baseline.
- `4b96d37`: the closed-window filter rebuilt each window's IPC map on every
  layout tick; it reads the address property instead.
- `bfb0438`: `HistoryGrouping`'s run-key comment still assumed arrivals at
  index zero.
- An older notification that history slots in below a run's tail changed the
  run's key, so a run the user had opened folded again. `HistoryGrouping`
  now carries the open state to the new tail.

Kept as upstream by the maintainer's call: the calendar's prev and next
arrows take the disabled look while the card fades out and fade up from it on
open. The window's input mask and `_go`'s guard already block input while
closed, so the gate is redundant but harmless.

Open:

- `SystemTools` now calls the `Compositor` facade, which reaches back into
  `SystemTools` through `HyprDispatch`. Every reference sits in a function
  body, as upstream's does, so construction order is unaffected.

## Not yet verified live

- The calendar at 1.6×: `SUN MON …` headers, the 32 px nav row, and the
  arrows' disabled look during the fade-out.
- Lock from the menu, then a shell restart: hyprlock keeps running.
- Reboot from the countdown, cancelled in hyprshutdown: the bar comes back.
- A slider and the hue and saturation handles pressed off centre.
- A Pill whose text changes quickly, such as the recording timer.
- Two media players, the most recently started one on the card.
- A Wi-Fi connect during a rescan.
