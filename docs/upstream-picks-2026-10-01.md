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
- A consistency pass over the integrated branch: the underline's
  temperature sweep aims at the vitals widget's TEMP chip when it is placed,
  the bar media widget's accessible press action opens the card as a click
  does, row dividers snap to the window's own pixel ratio, the clock's date
  peek follows its hover gate, and stale or history-narrating comments now
  state their current reasons.
- Found by an external adversarial review of the integrated branch:
  - The power mode IPC refused forever from a keybind. Only an open surface
    read the profile, so a cycle before any popup opened always found it
    loading. The refusal now starts the profile read and listing, so a retry
    works.
  - `BoundedProcess` and `SupervisedProcess` lost a chained command's failed
    start. Quickshell emits `exited` before `runningChanged`, so a command
    started from `exited` inherited the finished run's exit flag. The flag
    now clears when a run starts (ledger entry).

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
- The recording watch gives up only on exec failure (126/127). The timezone
  watch runs inotifywait without a shell, so a missing binary retires it
  through SupervisedProcess's failed-start path. A transient inotify limit
  stays retryable in both.
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
source are fork fixes found during review. Ledger updates ride in the commit
that creates the divergence: the icon roots' entry is part of the notify-send
icon commit, the DND IPC route's entry is part of the IPC toggle commit, and
the process exit flag's entry is part of its fix.

| Commit | Subject | Upstream source |
| --- | --- | --- |
| `2db0a1d` | fix(notif): quote the daemon-conflict owner strip for bash | afcf716 |
| `626ce60` | fix(notif): focus the inline reply field without requestActivate | 4aadfc0 |
| `ac48af4` | fix(notif): read the progress hint as a percentage | 69ded98 |
| `40a9267` | fix(notif): clamp a sender's timeout instead of discarding it | 114a62d |
| `2c614dc` | fix(notif): strip wider markup and entities, expire suppressed ones | afcf716 |
| `f7fed6e` | fix(notif): restart a replaced popup's timeout and cap live cards | e4b7517 |
| `0aaaf88` | feat(layer): show notifications and popups over fullscreen windows | 8a53f65 |
| `a754ee8` | feat(notif): resolve notify-send icons from the theme and system dirs | 7d324d6 |
| `53a45a3` | fix(notif): hold popup timeouts while the user is away | f549edf, afcf716 |
| `1338377` | fix(text): cluster Indic marks and bound labels before scanning | 01a157d |
| `2dacb27` | fix(night-light): find the timezone tables on nixos | fork fix |
| `92cc6bc` | fix(night-light): match published sunrise and sunset times | 2f83b3b |
| `3d1f297` | perf(osd): skip building the floating osd while the bar shows it | 2f83b3b |
| `708a583` | feat(night-light): draw the whole day on the arc and name the next sun event | 3f19cac, d7a4dbe |
| `dd5e547` | fix(alerts): keep test shells from sending live alerts | 37743d0 |
| `21462ac` | fix(alerts): re-arm battery warnings only after a margin | 01a157d |
| `d476dd6` | test(lint): require a give-up path on every supervised process | 192abbd |
| `7e3c89a` | test(check): make the startup dwell checks and the bidi scan real | 0093a26 |
| `70d87eb` | test(lint): flag a misspelt singleton member in the connections check | 18f7546 |
| `9a37b84` | fix(scripts): read the quickshell version past qt's locale warning | a191143 |
| `bf0bfc6` | fix(power): drain the confirmation ring with one animation | 9dd66d6 |
| `832a97e` | fix(vitals): gate the cpu alert pulse on the home page | 4843c1f |
| `24d06ed` | feat(vitals): snap small usage steps, wait for cpu, wrap tiles at large fonts | 7a1b3a2, 36eb781, 2278678 |
| `43fdee1` | fix(bluetooth): trust newly paired devices and wait on a connecting one | 241ccdf |
| `3ce6b3b` | feat(power): add log out to the power rail | 2f163b3, bea91dd |
| `2404a9a` | fix(power): show power mode failures in the rail and quick actions | 805dbbe |
| `d20ec6f` | fix(menu): let the wheel keep scrolling the page past sliders | f836ae0 |
| `99536df` | fix(settings): put slider defaults on their step grid and lint it | f836ae0, 8bd0f4c |
| `95fa230` | fix(common): snap hairlines, outlines and progress rings to device pixels | b35b2dd |
| `e2bf8e7` | fix(underline): centre the temperature sweep and clear a stopped net-loss flash | 2278678 |
| `327462c` | fix(system): skip failing sensors and quiet the polling that outlives idle | 2278678, 498bb19 |
| `82669e9` | fix(system): read disk usage as df does and keep rate columns four wide | 01a157d |
| `af1a099` | fix(wifi): list saved networks first and disconnect by name | 36eb781 |
| `0f131b8` | fix(wifi): name the password field for screen readers | 8638488 |
| `46ea54f` | fix(menu): ignore taps on busy wi-fi and bluetooth rows | 2e57faa |
| `b87da0f` | fix(settings): disable the alert timeout without notify-send | 70d32a6 |
| `f1a8fc9` | fix(notif): expire cards into history when the session goes idle | f549edf |
| `ac1fa64` | feat(layer): put the remaining popup surfaces on the overlay layer | 8a53f65 |
| `59f2312` | fix(bar): hold pill hover state to the bar's sleep and hide gates | e335887 |
| `7b99340` | fix(traymenu): close the menu when the bar changes edge | eb91b95 |
| `a360a70` | fix(tray): reset a tile's icon state when it takes a new app | e2ef3ac |
| `52fcbdb` | fix(bar): guard the enter animation against teardown | f478556 |
| `9c11618` | fix(tray): send apps whole scroll steps from a touchpad | 0106da1 |
| `95813fd` | fix(traymenu): let the menu openers alone signal submenu open and close | d2a1a01, b92abc1, 95654ac |
| `3b41ee0` | fix(compositor): read hyprland fullscreen as a bitmask | 36eb781 |
| `cb3129b` | fix(hyprland): take the lua dispatch form from hyprland itself | 01a157d |
| `870a1ee` | fix(workspaces): activate from named workspaces and track special per output | 01a157d |
| `a3ca575` | fix(workspaces): ease row width off its own slot and fade icons with the dot | 36eb781 |
| `b7a4e4c` | fix(workspaces): trim the empty edges of the row so the next divider centres | 5dd6016 |
| `1aabfd6` | fix(windowtitle): keep the divider through a title crossfade and strip spinner glyphs | 36eb781 |
| `5b154f0` | fix(time): catch the clock up after suspend | 36eb781 |
| `515ac3e` | perf(media): step the progress line in whole pixels and scroll a title twice | 52a9804, 498bb19 |
| `064e983` | fix(media): crossfade album art without the card showing through | 442ba70 |
| `07fe24f` | fix(windows): match a browser player by whole class token | 498bb19 |
| `1f53cf1` | fix(brightness): follow hotkey changes, set the raw level and step on the grid | 498bb19, db78021, 01a157d, 36eb781 |
| `d02c926` | fix(battery): name a held charge and keep level wheels natural | 36eb781 |
| `822cd6c` | fix(screenshot): ignore photos in the pictures root and tie the watcher to qs | 01a157d, da8dfd4 |
| `92d8150` | refactor(hooks): drop the unread scan flag | 9ac55b1 |
| `1b82aad` | feat(clock): add a hover cap, date peek and tabular digits | 861234d, 36eb781 |
| `6deca01` | fix(persistence): hold debounced writes while a watched file reloads | da8dfd4 |
| `afef8ea` | fix(process): report a spawn failure instead of hanging callers | da8dfd4 |
| `c0aceb2` | fix(calendar): normalize mark keys and reload the file when it changes | da8dfd4 |
| `fa252ac` | fix(settings): keep a newer release's out-of-range values and string versions | da8dfd4 |
| `e2ac80d` | fix(settings): apply reloads as a diff and answer IPC errors with error: | a447463 |
| `ad14cda` | feat(calendar): add week start and week number settings | 3e1a018, cc23591, 0662c9f |
| `5e64366` | fix(menu): gate page transitions on the shared motion check | d2f87cf |
| `da23886` | fix(menu): fold an open settings dropdown before escape closes the menu | debcba6 |
| `b0072a9` | fix(menu): hold the menu height before an IPC tab change | 74368ba |
| `69fc68e` | feat(quickactions): toggle dnd, night light, power mode, wifi and bluetooth over IPC | 92dee26 |
| `71745f0` | fix(settings): keep page-less keys out of the reset offer and report IPC toggle results | 498bb19 |
| `3ddffce` | fix(settings): refuse a symlinked config dir, trim IPC keys, queue strip drags | 2278678 |
| `629263d` | fix(settings): drop float residue from slider steps and saved reals | d6231ea |
| `3b8a8fa` | fix(menu): scroll an opened dropdown into view and wrap the settings error | b35b2dd |
| `ae4556e` | docs(media): warn about web cover art under its toggle | c7e1364 |
| `12f8b9e` | style(text): raise muted text contrast across popups and the menu | 8a53f65 |
| `3a858ab` | fix(system): recover a sensor that failed one read | 2278678 |
| `2a870cb` | fix(traymenu): signal every reshow of the same menu | d2a1a01, b92abc1, 95654ac |
| `ce3b8c9` | fix(time): derive every non-tick clock update from a fresh Date | fork fix |
| `d5e984b` | fix(clock): drop the hover cap when the bar idles | 861234d |
| `dab70ed` | fix(settings): name a symlinked config dir instead of claiming it could not be created | 2278678 |
| `58fd13c` | fix(quickactions): give each refused IPC toggle its own reply | 92dee26 |
| `2aa6957` | fix(calendar): number today's week the way its row does | 3e1a018 |
| `5c192a1` | fix(motion): time each motion by the value it is heading to | 9c598f6 |
| `ba4ace4` | docs(settings): give the applied-text skip its current reason | fork fix |
| `7cab0a4` | fix(time): drop the shell exit codes the timezone watcher cannot return | fork fix |
| `e835777` | fix(underline): sweep a temperature warning to the vitals widget | fork fix |
| `d0a43bc` | test(lint): report singleton members in the connections check's wording | fork fix |
| `bd4def6` | docs(probe): finish the spawn-failure checks' comment | fork fix |
| `6b1b563` | docs(comments): state rationale in the present instead of narrating changes | fork fix |
| `a1139c6` | refactor(install): drop the callerless hyprland config-kind helper | fork fix |
| `6ca9197` | fix(menu): snap row dividers to the window's own pixel ratio | fork fix |
| `a37745d` | refactor(menu): read the open settings dropdown through a public accessor | fork fix |
| `cccf016` | refactor(night-light): name the sun arc's span once for canvas and labels | fork fix |
| `0cc9c89` | fix(clock): gate the date peek on the clock's hover gate | fork fix |
| `38d6383` | style(text): align the reserve metrics and alignment property with their blocks | fork fix |
| `d3344c6` | fix(media): open the card from the bar widget's accessible press action | fork fix |
| `82e1fbe` | docs(upstream): rewrap the bluetooth pairing entry | fork fix |
| `a3f6998` | fix(quickactions): start the power mode read when an IPC cycle finds none | fork fix |
| `c235647` | fix(process): clear the exit flag when a chained run starts | fork fix |

## Validation

- Every commit passes `bash scripts/ci-lint.sh`, and the settings contract
  holds at each one (54/54 before the calendar keys, 56/56 after).
  nixos-config's silere module renders the same 56 keys.
- `nix develop . --command bash scripts/check.sh` passed at every stream
  checkpoint and at the last implementation commit, with zero failures and the
  four standing environmental warnings (powerprofilesctl, compositor autostart,
  two Matugen entries). PROBE-LOGIC grows from 411 to 479 checks.
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
- Accepted risk: once read, the power profile is not re-read while every
  surface is closed, so a change made elsewhere (an `asusctl` hotkey) leaves
  it stale and an IPC cycle steps from the stale value. Closed surfaces
  stay unpolled by design.

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
- Hairline, outline and row divider snapping at 1.6×; muted text contrast.
- Motion: the first hover or press after a reversal; the settings nav slide
  now uses collapse timing when power opens on the settings tab.
- Wheel scrolling past settings sliders; right-click forget on Wi-Fi and
  Bluetooth rows; pairing leaves a device trusted.
- Power mode IPC from a keybind before any popup opens.
