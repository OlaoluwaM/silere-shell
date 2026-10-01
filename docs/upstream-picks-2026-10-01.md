# Selective upstream integration: v1.2.0 and the late-September fixes

Status: implemented and gated; live Hyprland checks listed under
[Not yet verified live](#not-yet-verified-live) are pending. Base:
`58b79462cb2418b9a309d06a170a0ba27df8c8fe`.

## Review range

The review covers the 144 upstream commits after
`d07d50981c7ec3348449120240fcd79961b11e2f` (v1.1.1), through
`ada88891b980df92b8739aa3824f41c70d7b7bf5` on `upstream/main` (2026-09-29), including the v1.2.0 release.
Sources are from <https://github.com/s3rven/silere-shell>.

The maintainer approved every applicable change except those declined below,
after reviewing the protocol blur and the clock highlight separately. A lead
split the work into five implementation streams by file ownership, reviewed
each stream's diffs, and ran an adversarial review on the four streams with
correctness-sensitive changes. Confirmed findings went back to the streams as
new commits before integration.

## Declined and skipped

- Declined by the maintainer:
  - Notification history search (`dc6d6c6` and the search hunks of `2e57faa`).
  - The protocol blur chain (`995f262`, `d13d351`, `5aca380`, `b21d987`).
    The Hyprland layer rule already blurs every `silere-*` surface. Declared
    regions would mainly withhold blur during fades and change the open
    animation, and need a Hyprland 0.56 session to validate.
  - The niri fullscreen and event-library work (`5a3054b`, `d9265d5`).
- Upstream's calendar-open tint on the clock (`861234d`): the fork takes the
  hover and pressed caps only, matching the other pills.
- Already covered: battery auto-hide on AC (`498bb19` hunk; the fork's
  `Battery.charging` already means "not on battery"), the Hyprland hyprsunset
  update (`6d57353`), probe state isolation (`bb11747`), menu retention and
  migration backups.
- Upstream policy kept as is: the 50-card overflow cap has no critical
  exemption, a sender updating in place keeps its popup alive, and
  `SafeText.singleLineText` keeps upstream's pre-collapse bound and
  zero-width handling.
- Skipped, absent in the fork: FilteredHistory, RecentNav and the app rail
  (`49aa0dd`, `844d940`, `1e64f43`), the pooled Wi-Fi rows (`9cbc575`, whose
  gate would bypass the palette fade), the update card grid (`4d4fc3e`),
  the forget-and-repair hint (`b00e65a`), the pending-only-when-slow power
  label (`44be905`), the window-title app-name cache (`3b2c10c`), the
  workspace slot model (`ada8889`, ledger: dynamic workspaces), the bar
  spectrum (`d64fd74`) and cava give-up (`ed273b1`).
- Skipped under the keep-deleted list: the updater, `silere` CLI, doctor,
  installer, AUR, release, workflow, changelog and README commits.
- Deferred: `a98461c` still needs the deferred compositor-restart watcher.
- Not ported: the concurrent smoke runner from `18f7546` (smoke cases stay
  sequential), `f61186a`'s lints for absent features, `1609373`'s Qt floor
  (Nix pins Qt), and `7873a48` (the fork has no long-running sunset process).

## Fork fixes found during review

- The night light read `/usr/share/zoneinfo`, which NixOS lacks, so its
  location always fell back to 45°N. It now searches `$TZDIR`,
  `/etc/zoneinfo`, then `/usr/share/zoneinfo`.
- Several clock refreshes read `SystemClock.date`, which lags a timezone
  switch by up to a tick. Every refresh that is not SystemClock's own
  `dateChanged` now passes a fresh `Date`.

## Material adaptations

- Notifications: suppressed notifications are archived, then expired, so
  history still receives them once. The away pause pairs with an expiring
  dismissal when the session goes idle. Icon roots add the Nix profile and
  `XDG_DATA_DIRS` locations to upstream's FHS roots (ledger entry).
- Every popup surface, including the fork's keybinds, media, tray and
  wallpaper popups, uses the Overlay layer; the bar hint stays with the bar.
- Muted text contrast is one commit across the fork's surfaces, including the
  grouped history body. The removed history chevron has no counterpart.
- Tray menus signal open and close only through `QsMenuOpener` reference
  counting, including a reopen during the fade and the drill-in lane.
- Hyprland: fullscreen is the `& 2` bit, and the Lua dispatch form follows
  `Hyprland.usingLua` instead of a config-file probe.
- Log out uses `hyprshutdown` when installed, else Hyprland's exit dispatch.
- Supervised watchers give up only on exec failure (126/127) for the timezone
  and recording watches, so a transient inotify limit stays retryable.
- CPU temperature: a sensor that fails one read is skipped for the next scan
  only; a scan emptied by rejects alone retries instead of latching missing.
- Calendar: the week-number header follows the same rule as today's row, so
  a Sunday start shows one number. The popup keeps `new Date()` instead of
  `DateTime.currentDate` (ledger entry). nixos-config declares the two new
  keys, with a Sunday week start for this desktop.
- IPC: quick-action toggles route DND through the fork's duration picker
  (ledger entry) and reply `error:` for refusals, in-flight changes,
  hard-blocked radios and services still starting.
- The symlinked config directory refusal names the symlink.

## Fork commits

Each commit names its upstream sources in a `Source:` line. Commits without a
source are fork fixes found during review.

| Commit | Subject | Upstream source |
| --- | --- | --- |
| `2db0a1d` | fix(notif): quote the daemon-conflict owner strip for bash | afcf716 |
| `626ce60` | fix(notif): focus the inline reply field without requestActivate | 4aadfc0 |
| `ac48af4` | fix(notif): read the progress hint as a percentage | 69ded98 |
| `40a9267` | fix(notif): clamp a sender's timeout instead of discarding it | 114a62d |
| `2c614dc` | fix(notif): strip wider markup and entities, expire suppressed ones | afcf716 |
| `f7fed6e` | fix(notif): restart a replaced popup's timeout and cap live cards | e4b7517 |
| `0aaaf88` | feat(layer): show notifications and popups over fullscreen windows | 8a53f65 |
| `43ed7a5` | feat(notif): resolve notify-send icons from the theme and system dirs | 7d324d6 |
| `e6022c3` | fix(notif): hold popup timeouts while the user is away | f549edf, afcf716 |
| `24d6a47` | fix(text): cluster Indic marks and bound labels before scanning | 01a157d |
| `da2885e` | fix(night-light): find the timezone tables on nixos | fork fix |
| `7811214` | fix(night-light): match published sunrise and sunset times | 2f83b3b |
| `f72bd9c` | perf(osd): skip building the floating osd while the bar shows it | 2f83b3b |
| `3bd57e5` | feat(night-light): draw the whole day on the arc and name the next sun event | 3f19cac, d7a4dbe |
| `213a5df` | fix(alerts): keep test shells from sending live alerts | 37743d0 |
| `b4a2582` | fix(alerts): re-arm battery warnings only after a margin | 01a157d |
| `e2562bc` | test(lint): require a give-up path on every supervised process | 192abbd |
| `ea6a0e9` | test(check): make the startup dwell checks and the bidi scan real | 0093a26 |
| `ae5664c` | test(lint): flag a misspelt singleton member in the connections check | 18f7546 |
| `4d53a7e` | fix(scripts): read the quickshell version past qt's locale warning | a191143 |
| `3df0056` | fix(power): drain the confirmation ring with one animation | 9dd66d6 |
| `60be264` | fix(vitals): gate the cpu alert pulse on the home page | 4843c1f |
| `c35e4b0` | feat(vitals): snap small usage steps, wait for cpu, wrap tiles at large fonts | 7a1b3a2, 36eb781, 2278678 |
| `37105fb` | fix(bluetooth): trust newly paired devices and wait on a connecting one | 241ccdf |
| `40e963f` | feat(power): add log out to the power rail | 2f163b3, bea91dd |
| `fde5c02` | fix(power): show power mode failures in the rail and quick actions | 805dbbe |
| `718a2fc` | fix(menu): let the wheel keep scrolling the page past sliders | f836ae0 |
| `3844f98` | fix(settings): put slider defaults on their step grid and lint it | f836ae0, 8bd0f4c |
| `c31f05b` | fix(common): snap hairlines, outlines and progress rings to device pixels | b35b2dd |
| `48ba2fb` | fix(underline): centre the temperature sweep and clear a stopped net-loss flash | 2278678 |
| `16c9a77` | fix(system): skip failing sensors and quiet the polling that outlives idle | 2278678, 498bb19 |
| `0b8ce9d` | fix(system): read disk usage as df does and keep rate columns four wide | 01a157d |
| `e6a0d11` | fix(wifi): list saved networks first and disconnect by name | 36eb781 |
| `95ba713` | fix(wifi): name the password field for screen readers | 8638488 |
| `54ca016` | fix(menu): ignore taps on busy wi-fi and bluetooth rows | 2e57faa |
| `856dd4d` | fix(settings): disable the alert timeout without notify-send | 70d32a6 |
| `a13ac0e` | fix(notif): expire cards into history when the session goes idle | f549edf |
| `e28f4ae` | docs(icons): state the icon roots' trust and record the divergence | 7d324d6 |
| `e0c5509` | feat(layer): put the remaining popup surfaces on the overlay layer | 8a53f65 |
| `60c492d` | fix(bar): hold pill hover state to the bar's sleep and hide gates | e335887 |
| `c73f6ce` | fix(traymenu): close the menu when the bar changes edge | eb91b95 |
| `2b4482b` | fix(tray): reset a tile's icon state when it takes a new app | e2ef3ac |
| `315d3d5` | fix(bar): guard the enter animation against teardown | f478556 |
| `ec2e5f1` | fix(tray): send apps whole scroll steps from a touchpad | 0106da1 |
| `0dc2c3e` | fix(traymenu): let the menu openers alone signal submenu open and close | d2a1a01, b92abc1, 95654ac |
| `c7204c6` | fix(compositor): read hyprland fullscreen as a bitmask | 36eb781 |
| `29086a5` | fix(hyprland): take the lua dispatch form from hyprland itself | 01a157d |
| `bdb9289` | fix(workspaces): activate from named workspaces and track special per output | 01a157d |
| `27b6aac` | fix(workspaces): ease row width off its own slot and fade icons with the dot | 36eb781 |
| `c2c168c` | fix(workspaces): trim the empty edges of the row so the next divider centres | 5dd6016 |
| `e8638f7` | fix(windowtitle): keep the divider through a title crossfade and strip spinner glyphs | 36eb781 |
| `b52d798` | fix(time): catch the clock up after suspend | 36eb781 |
| `616fbfd` | perf(media): step the progress line in whole pixels and scroll a title twice | 52a9804, 498bb19 |
| `1ad5a9a` | fix(media): crossfade album art without the card showing through | 442ba70 |
| `0e6d68f` | fix(windows): match a browser player by whole class token | 498bb19 |
| `75d3cdc` | fix(brightness): follow hotkey changes, set the raw level and step on the grid | 498bb19, db78021, 01a157d, 36eb781 |
| `f6c4dbe` | fix(battery): name a held charge and keep level wheels natural | 36eb781 |
| `6977618` | fix(screenshot): ignore photos in the pictures root and tie the watcher to qs | 01a157d, da8dfd4 |
| `09af077` | refactor(hooks): drop the unread scan flag | 9ac55b1 |
| `ae6c2ca` | feat(clock): add a hover cap, date peek and tabular digits | 861234d, 36eb781 |
| `52f2d4e` | fix(persistence): hold debounced writes while a watched file reloads | da8dfd4 |
| `121bbd4` | fix(process): report a spawn failure instead of hanging callers | da8dfd4 |
| `cf39390` | fix(calendar): normalize mark keys and reload the file when it changes | da8dfd4 |
| `14be2ee` | fix(settings): keep a newer release's out-of-range values and string versions | da8dfd4 |
| `011f77f` | fix(settings): apply reloads as a diff and answer IPC errors with error: | a447463 |
| `cf41c22` | feat(calendar): add week start and week number settings | 3e1a018, cc23591, 0662c9f |
| `757e348` | fix(menu): gate page transitions on the shared motion check | d2f87cf |
| `f2dce0d` | fix(menu): fold an open settings dropdown before escape closes the menu | debcba6 |
| `8a1329d` | fix(menu): hold the menu height before an IPC tab change | 74368ba |
| `1227be7` | feat(quickactions): toggle dnd, night light, power mode, wifi and bluetooth over IPC | 92dee26 |
| `4195de9` | fix(settings): keep page-less keys out of the reset offer and report IPC toggle results | 498bb19 |
| `ae8a2b4` | fix(settings): refuse a symlinked config dir, trim IPC keys, queue strip drags | 2278678 |
| `f3a4780` | fix(settings): drop float residue from slider steps and saved reals | d6231ea |
| `fee340b` | fix(menu): scroll an opened dropdown into view and wrap the settings error | b35b2dd |
| `c108724` | docs(media): warn about web cover art under its toggle | c7e1364 |
| `4b33025` | style(text): raise muted text contrast across popups and the menu | 8a53f65 |
| `a4255f8` | fix(system): recover a sensor that failed one read | 2278678 |
| `b782315` | fix(traymenu): signal every reshow of the same menu | d2a1a01, b92abc1, 95654ac |
| `5784c4e` | fix(time): derive every non-tick clock update from a fresh Date | fork fix |
| `5958478` | fix(clock): drop the hover cap when the bar idles | 861234d |
| `34632ad` | fix(settings): name a symlinked config dir instead of claiming it could not be created | 2278678 |
| `ecbe20a` | fix(quickactions): give each refused IPC toggle its own reply | 92dee26 |
| `9e8f99b` | fix(calendar): number today's week the way its row does | 3e1a018 |
| `3beeae0` | docs(upstream): record the dnd IPC toggle's route through the duration picker | 92dee26 |
| `d264eae` | fix(motion): time each motion by the value it is heading to | 9c598f6 |

## Validation

- Every commit passes `bash scripts/ci-lint.sh`, and the settings contract
  holds at each one (54/54 before the calendar keys, 56/56 after).
  nixos-config's silere module renders the same 56 keys.
- `nix develop . --command bash scripts/check.sh` passed at every stream
  checkpoint and at the last implementation commit, with zero failures and the
  four standing environmental warnings (powerprofilesctl, compositor autostart,
  two Matugen entries). PROBE-LOGIC grows from 411 to 476 checks.
- The notification stack test drives a real Wayland surface and needs a lit
  display. With the display off and locked it fails on every commit,
  including the untouched base, so the final full run waits for a lit
  session.
- Adversarial reviews covered the notification, bar and tray, settings and
  IPC, system-control and motion changes. Each confirmed finding was fixed in
  its own commit or folded into the change it corrected; upstream-identical
  behaviour and accepted risks are listed above.
- Coverage limits: offscreen probes cannot drive real idle, suspend, tray
  D-Bus menus or Hyprland IPC. The tray signalling and the Lua dispatch
  binding were checked against the Quickshell 0.3.1 source, not live.

## Not yet verified live

- Popups over a fullscreen window, including menu and calendar keyboard focus.
- Notifications that arrive while away: paused, then expired into history at
  idle. Inline reply focus. `notify-send -i <icon-name>` icons.
- Tray menus: reopen during the fade, drill in and back, bar edge change with
  the menu open.
- Hyprland: `HyprDispatch.useLua` follows `Hyprland.usingLua`; named
  workspace clicks; fullscreen mode 3.
- Clock: hover cap, date peek with the date off, steady width at 1.6×.
- Calendar with a Sunday start and week numbers.
- Night light arc, off-status text, and sun times in 12-hour mode.
- Log out arm and confirm (without firing it). `hyprshutdown` is not
  installed, so Log out uses Hyprland's exit dispatch.
- Hairline and outline stroke snapping at 1.6×; muted text contrast.
- Motion: the first hover or press after a reversal; the settings nav slide
  now uses collapse timing when power opens on the settings tab.
- Wheel scrolling past settings sliders; right-click forget on Wi-Fi and
  Bluetooth rows; pairing leaves a device trusted.
