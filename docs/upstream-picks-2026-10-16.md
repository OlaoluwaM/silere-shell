# Selective upstream integration: the October 16 fixes

Status: implemented and gated; reviews in progress. Base:
`dcb8e708167fb5f86cee6e160b8fffba65c5d422`.

## Review range

The review covers the 51 upstream commits after
`dab16d682b36959b251a13b58ca6d26a988dc620` through
`53c91378a1315cbfffa73b408ad3c62457c16e2f` on `upstream/main`, dated October 9
to 11 and spanning the 1.4.1 and 1.4.2 releases. Sources are from
<https://github.com/s3rven/silere-shell>. The maintainer chose the bug fixes;
features were offered separately. Upstream keeps its probes in
`dev/probe-logic.qml`, which the fork's smaller `scripts/` probes do not
mirror, so every fork commit ports its checks by hand.

## Selected

| Commit | Subject | Upstream source |
| --- | --- | --- |
| `cd606d0` | fix(text): find useful error summaries without splitting entire logs | 96e63e1 |
| `55fa261` | fix(scroll): reuse one cleanup timer for wheel gestures | 482e950 |
| `f9cf9bd` | fix(notifications): keep deadlines on time after the clock steps back | 61f8737 |
| `9c3871d` | fix(nightlight): estimate the fallback longitude from standard time | 5e7098c |
| `e8ca6a5` | fix(motion): guard disclosure settle timers during async teardown | 35c8cf2 |
| `e702bde` | fix(nightlight): keep hyprsunset neutral in daylight | 1740d78 |
| `a61bdb2` | fix(brightness): move a notch at least one level on coarse backlights | ae3e646 |
| `d8192e7` | fix(process): treat a helper that exits after its deadline as failed | 3c43bd2 |
| `d1d7945` | fix(controls): ignore hidden menu controls | 2fa972c |
| `e6b68e1` | fix(controls): cancel expired confirmations | fc62faa |
| `288d858` | fix(network): follow wifi scan demand when adapters change | 66d5194 |
| `71513c0` | fix(niri): clear windows and workspaces when its socket drops | 9727ca6 |
| `1442514` | fix(notifications): let an app raise its own window from a click | 1252569 |
| `ccc1b0e` | fix(notifications): drop markdown bold markers from notification text | 3569ed1 |
| `a35a022` | test(text): write the error-summary bidi override as an escape | follow-up to 96e63e1 |

Taken earlier, with the October 14 and 15 VPN work: `d1b3154` (tunnel changes
within seconds) and `6adfca3` (the VPN address in Connectivity and the network
hover text).

## Material adaptations

- Deadlines: the update services and `SystemTools.refreshIfStale` hunks have
  no counterpart in the fork. The notification check reads the card's
  elapsed time instead of upstream's timer helper.
- Night light: the fork drives its Nix-managed `hyprsunset.service` over
  `hyprctl` and has no provider argv, so the daylight identity matrix is
  chosen in `NightLight.temperatureArgv`, which both temperature pushes use.
- Helper deadlines: the fork has no unit or blur probe in
  `CompositorHyprland`. Its location reader has no retry flag, so a timed-out
  read is ignored. The VPN readers move from `code === 0` to
  `completedSuccessfully`, as upstream's do; they used the exit code only
  because this helper was missing.
- Hidden controls: the fork's chip and swatch rows have no gliding selection
  ring, so only the input gating is taken, not the ring-range half.
- Confirmations: only the confirm button half of `fc62faa`. The slider half
  needs upstream's SliderTrack rework (below).
- Probes: toggled visibility hosts sit inside a fixed parent item, because a
  parentless item cannot be shown again once hidden.

## Pending the maintainer's decision

- `4885fb4` (sliders drop input when their device changes) and `29dbf45`
  (bar pills reset hover and wheel state when their target changes). Both,
  and the slider half of `fc62faa`, build on the interactive SliderTrack and
  `QuickSlider.adjustable` from `9d3b66a`, which the October 10 record left
  as a later candidate. Taking them means importing that slider work first.

## Declined, deferred and skipped

- Already handled by the fork:
  - `a31b9e0` (warn when the battery is already critical at login):
    `SystemAlerts` checks the current level at startup.
  - `4e8ed63` (hold settings writes until the migration backup lands): the
    fork's backup is a blocking write that finishes before writes are
    allowed.
  - `a04cc95` (match the whole history entry when removing it): the Recent
    page removes rows by index, so no caller matches entries.
- Features, offered and not selected in this round: notification history
  expiry (`a9cfaec`, a settings key), sideways drag to dismiss (`bd6b5e4`),
  right and middle click on history rows (`72832ed`), the tray submenu pause
  (`ccca19a`), the Bluetooth forget hint (`d6e5253`), the stable media player
  list (`9ee2a41`), settings search (`a2f2482`), the rounded history search
  field and calendar month button (`2a42646`), settings page icons
  (`7af1c47`), and moving popups off an unplugged output (`c1a3d96`, built on
  upstream's Keep Awake surface).
- The fork has its own feature: the timed DND (`27fbae2`) and the Nix-declared
  lock command (`a0e409e`).
- Built on work the fork deferred or does not have: the fitted popup window
  (`91df8f5`), `PixelSnap` and `SmoothGlide` (`45ee2d2`), `PwVolumeControl`
  (`6122499`), the Now Playing page (`750bb8f`).
- Not applicable with this configuration: the underline glow polish
  (`ed91756`, `a8613e9`, `378d5c7`, `27cc7b3`); the underline glow is off here.
- Removed from the fork: the visualizer (`c75719c`, `34c2803`), package
  updates (`10ab0e2`), doctor, troubleshooting, release, performance,
  installer, benchmark, KWin and CI commits (`7bc9dc9`, `f184b53`, `b8b0885`,
  `0c1372c`, `9e27364`, `53c9137`, `5933d34`, `4e467c3`, `961f9f5`,
  `c4a4851`), and the test-only `cc1e8d0`.

## Validation

`bash scripts/ci-lint.sh` passes and
`nix develop . --command bash scripts/check.sh` reports zero failures with the
four known environmental warnings. `PROBE-LOGIC` passes 628 checks,
`PROBE-UPSTREAM-SERVICES` 15 and `PROBE-UPSTREAM-TRAY` 10, including the
ported cases. The Niri checks feed the backend mock events; no live Niri
session was involved. The hyprsunset `identity` request was not sent to the
live desktop.

## Not yet verified live

- Night light in auto mode at full daylight sends `identity` and the screen
  shows no tint.
- Clicking a kitty notification with several kitty windows keeps the window
  kitty raised.
