# Lock screen: design and plan

Status: design locked on 2026-10-26; architecture reworked the same day after
five adversarial reviews; implementation not started. Work happens on the
`lock-screen` branch here and on a matching branch in nixos-config. The
interactive mockup is the "Silere Lock Screen" canvas
(<https://claude.ai/artifact/NQR3Fy1xRWXEJahSaHNo7P>, private to the maintainer).
Versions checked: Quickshell 0.3.1, Hyprland 0.55.4, hypridle 0.1.8.

The fork gains a lock screen that replaces hyprlock, built with Quickshell's
`WlSessionLock` and `PamContext`. It runs as its own short-lived Quickshell
process, started for each lock and exiting on unlock, exactly as hyprlock does:
a second entry point, `lock.qml`, beside `shell.qml` in the same tree, sharing
its `config/`, `services/` and components. It does not live inside the running
shell. An earlier version did, and every review found new races in the
handshake that required (IPC, readiness, crash markers, retries); a separate
process is independent of the bar's health in both directions and needs none of
that.

Bar widgets are not reused: the bar is a layer-shell `PanelWindow`, which cannot
draw above a session lock, and most of its widgets open popups or change
settings that must stay out of reach while locked. The lock reuses the services
the bar reads instead.

hyprlock stays installed as the fallback: the wrapper that starts the lock runs
hyprlock whenever the lock process fails (see Lock integrity).

## Design

Minimal on purpose: one element per corner, nothing that needs the session to
be unlocked to be useful. Colours come from `Theme` tokens, so the lock follows
the wallpaper palette like every other surface. Pixel values are at the
mockup's 1440x900 logical size.

| Area | Content |
| --- | --- |
| Background | The surface's own `color` is the theme background token (Quickshell's default is white). Over it, the current wallpaper from `lockWallpaper` (see Settings), blurred and dimmed. `wallpaper-set` renames a new file over that path, so the `Image` uses `cache: false`, resets its source on every lock, and loads `asynchronous: true` so decoding never delays the first frame Hyprland waits for. An empty path or `Image.Error` leaves the plain background. |
| Top-left | Clock at 148px, weight 200, letter-spacing -0.04em (about -5.9px; Qt's `font.letterSpacing` is in pixels). Date at 20px in `Theme.subtext`, 18px below. The date's ink starts where the clock's ink starts. |
| Top-right | Battery glyph and percentage at 14px. Adds `· charging` while charging and `· plug in` below `ShellSettings.batteryLowThreshold`, in `Theme.error`. Hidden when `Battery.available` is false. The digits' ink top sits level with the clock's. |
| Bottom-left | User name, indented to the field's text inset (16px), over a 48px password field. Messages sit in the margin under the field so the field never moves: checking, wrong password with the attempt count, PAM messages, lockout. Caps Lock chip inside the field. A short shake on failure. Typed text clears after 10s idle; Esc clears it at once. |
| Bottom-right | When `lockPowerButton` is on (the default), a 48px power button, bottom edge level with the field. It opens a card in the quick-settings card style with Suspend, Reboot and Power off. Suspend runs at once. Reboot and Power off move to a countdown card that looks like the desktop's `PowerActionCard` (60s, Enter runs it now, Esc cancels) but is driven by the lock itself (see Power on the lock). A failure keeps the screen locked and shows the failure on the card. |
| Other outputs | Clock only. Typing works from any output; the PAM conversation and the typed text are shared. |

Deliberately left out: notifications (unreadable while locked), Wi-Fi state,
keyboard layout, and media. Playback already inhibits idle, so a locked screen
with music playing means a manual lock, and the media keys are `locked = true`
binds in nixos-config, so they work on the lock screen anyway.

### Font

A new `lockFontFamily` setting. Empty means "JetBrains Mono", and so does a
family that is not installed (checked through `FontScan`, as the shell font is).
Request plain "JetBrains Mono": nixos-config's fontconfig aliases "JetBrainsMono
Nerd Font" to Berkeley Mono for the bar.

Every alignment is read from the font at runtime, never from a table, so any
family works. The mockup's browser maths does not port, because Qt places text
differently: `lineHeight` below 1 scales the line box from the top while the
first baseline stays at `FontMetrics.ascent`, unlike CSS's centred leading. So
the clock drops `lineHeight` and positions by its ink:

- the clock's ink top is its `y + ascent + tightBoundingRect.y` (the tight
  rect's `y` is negative, measured from the baseline);
- the date's left offset is the clock's first-digit ink inset minus the date's
  first-letter ink inset (`TextMetrics.tightBoundingRect.x`);
- the battery row is placed so its digits' ink top equals the clock's.

`tightBoundingRect` and font features already have precedent in
`modules/common/ConfirmButton.qml` and `modules/common/CollapsingText.qml`.
Digits use tabular figures (`font.features: { "tnum": 1 }`) so a proportional
font does not shift sideways each minute. A family without weight 200 renders
the clock at its nearest weight. The mockup held to within 1px across JetBrains
Mono, Berkeley Mono, DejaVu Sans and Noto Serif; repeat that check in Qt.

### Settings

Few on purpose. Every key in `GeneratedDefaults.qml` is rendered by
nixos-config's `silere.nix`, so each setting here is also a Nix option. The
checked-in defaults are upstream-neutral, as AGENTS.md requires.

| Key | Kind | Checked-in default | Notes |
| --- | --- | --- | --- |
| `lockFontFamily` | string, `sec: "interface"` | "" (JetBrains Mono) | Row on the Interface page. Any installed family. The picker lists the default, the Nerd families and the current value, since previewing every `fc-list` family is too slow. |
| `lockPowerButton` | bool, `sec: "interface"` | true | Row on the Interface page. Off hides the power button and its card, leaving the lock with no actions. |
| `lockWallpaper` | string, `sec: "-"` | "" | Packaging-only, like `wallpapersDir`: no settings row, and only the Nix side writes it. |
| `lockCommand` | string, `sec: "-"` | "" | Packaging-only, like `wallpaperCommand`: the command the menu's Lock entries run, so they start the same wrapper hypridle does. Empty keeps today's behaviour (hyprlock, else `loginctl lock-session`). |

Reused rather than added: `clock12h` sets the clock format (the lock never shows
seconds) and `batteryLowThreshold` sets the plug-in warning. Fixed by the
design: colours, sizes, the 60s countdown, the 10s idle clear, and the blur.
`GeneratedDefaults.qml` comments must not contain the word "property": the
settings contract counts it with `grep -c`.

nixos-config adds one option of its own, outside the shell's settings:
`local.hyprland.lockScreen`, either `"hyprlock"` or `"follow-shell"`. It picks
the lock for the changeover and goes away in step 12.


## The lock process

`lock.qml` is a `ShellRoot` that locks as soon as it loads and exits when the
session is unlocked:

- **Only when the wrapper starts it.** `locked` is bound to `allowed`, which is
  true only when `SILERE_LOCK_WRAPPER=1` (set by the wrapper alone) and
  `SILERE_SANDBOX` is unset. Otherwise it logs why and exits 3 without ever
  creating a lock. A bare `qs -p lock.qml`, the usual dev loop, would otherwise
  lock the real session, and with no `/etc/pam.d/silere-lock` (on Fedora, say)
  nothing could unlock it. Refusing to lock is not an unlock bypass; there is no
  bypass or test unlock of any kind, in any build. The binding matters: a
  declarative `locked: true` would lock while the component is created, before
  any check runs.
- **Preview for design work.** With `SILERE_LOCK_PREVIEW=1` the same surface
  content draws in an ordinary `FloatingWindow` and nothing locks, so the layout
  can be iterated in the dev loop.
- **Locking.** `WlSessionLock`, one surface per output (Quickshell adds and
  removes surfaces on hotplug). The surface root stays trivial, with no
  `required` properties: if a new output's surface fails to be created,
  Quickshell unlocks the whole session. Hot reload is off for this instance
  (`settings.watchFiles: false`), so a file save never rebuilds a live lock.
- **Ready.** Once `secure` is true and the password field exists, the process
  writes the file named by `SILERE_LOCK_READY_FILE` and logs how long that took,
  to tune the wrapper's window. That, not `hyprctl locked`, is what the wrapper
  waits for. This one write deliberately bypasses the read-only settings gate.
- **Unlocking.** Only after `PamContext` reports success, against a dedicated
  `silere-lock` PAM config. The unlock fade runs, `locked` goes false, and one
  frame later the process exits 0 (`Qt.exit` sets the process status), so the
  unlock request is flushed first. Exit 0 means exactly that: the user
  unlocked.
- **Any other end exits non-zero.** The compositor ending the lock (`finished`,
  which Quickshell turns into an unlock it did not ask for) exits 2. A QML load
  error makes `qs` exit 255 on its own.
- **Settings are read, never written.** `//@ pragma Env
  SILERE_SETTINGS_READ_ONLY=1` in `lock.qml` turns on a read-only mode, applied
  before the engine starts. Loading settings writes in more places than
  `ShellSettings`, so the mode gates the low-level writers: `PersistedFile.flush`
  (which also covers `CalendarState`'s file), `ConfigStore`'s `ensureDirectory`,
  `hardenFile` and `pruneBackups`, and `ShellSettings._backupSettingsText`, which
  runs during migration before any other write check. Migration still happens,
  in memory.
- **Only the services it needs.** Singletons start on first use. The lock draws
  with `Theme`, `Settings`, `ShellSettings`, `Battery`, `FontScan` and
  `DateTime`, which pull in about 22 in all, including `Idle`, `MenuState`,
  `CalendarState`, `OverviewState`, the Hyprland compositor backend, and the
  `SystemTools` and `FontScan` probe processes. Those are allowed: none claims a
  session-wide resource. Their IPC handlers sit on the lock's own instance
  socket, and nixos-config's IPC calls target `shell.qml`. Forbidden: anything
  that owns a session-wide D-Bus name or service, such as the notification
  server, the tray watcher or MPRIS. Step 4 audits the graph and records the
  allowed list in `lock.qml`'s header comment.
- **Font settling never blocks the field.** `FontScan` runs `fc-list`
  asynchronously, never sets `scanned` if the scan fails, and can take up to 20s
  to time out. The lock waits at most about 1s for it, counts a failure as
  settled (falling back to JetBrains Mono), draws the background at once, and
  never holds back the password field.

## Lock integrity

The rules: a lock request must never end in an unlocked session, a failure must
never leave a session nobody can unlock, and there are never two lock clients
at once. All three are the job of one small wrapper, `silere-lock`, in
nixos-config (`writeShellApplication`, with `util-linux`, `procps`, `coreutils`,
`systemd`, Hyprland, Quickshell and hyprlock in `runtimeInputs`).

Every lock goes through it. Idle, Super+L and suspend reach hypridle through
`loginctl lock-session`, and hypridle's `lock_cmd` runs the wrapper. The menu's
Lock entries do the same: `lockCommand` renders `loginctl lock-session`, so the
menu takes the same path and environment as every other lock instead of
starting processes through Hyprland's `exec` with Hyprland's environment.

The wrapper runs under `writeShellApplication`'s `set -euo pipefail`, so every
command that may fail is captured rather than allowed to abort it: `rc=0; wait
"$pid" || rc=$?`, and likewise for `kill`, `flock -n`, `systemd-run`, and
`hyprctl` inside `$(…)`. An abort at the wrong moment would skip the hyprlock
fallback and leave the lockdead screen. Every wait is counted in `sleep 0.1`
iterations, never measured against the wall clock: suspend can freeze the
system in the middle of a window (with every output off, Hyprland confirms a
lock at once and hypridle lets the suspend proceed), and a clock that counts the
time asleep would kill a healthy lock on resume.

1. **Its own scope.** hypridle runs `lock_cmd` inside `hypridle.service`, which
   restarts on failure and whenever its settings change; a restart would kill
   the lock with it and leave the lockdead screen with no fallback. So the
   wrapper first re-runs itself with `systemd-run --user --scope --collect`,
   guarded by a variable so it happens once. In scope mode `systemd-run`
   returns the command's own status, so the outer run passes a marker path that
   the inner run touches first: `systemd-run … || [ -e "$marker" ] ||` run the
   rest unscoped. A user bus that cannot be reached must still produce a lock.
2. **One lock at a time.** Open the lock file on a dedicated descriptor
   (`exec {lockfd}>"$XDG_RUNTIME_DIR/silere-lock.lock"`) and take `flock -n` on
   it, held for the wrapper's lifetime; the wrapper lives as long as any lock
   client it started. Every child is started with that descriptor closed
   (`{lockfd}>&-`): `qs`
   passes inherited descriptors on to everything it spawns, and some of those
   outlive it (`TimeZoneWatch` runs `inotifywait -m` indefinitely; `fc-list`,
   `BoundedProcess` terminators and the PAM helper can too), which would hold
   the lock and make every later request skip. If the lock is already held, log
   and exit 0. Also exit 0 if a hyprlock started outside the wrapper is running
   *and* `hyprctl locked` reads true; a hyprlock that lingers holding nothing
   must not disable locking.
3. **Start the lock.** Create a fresh directory with `mktemp -d` under
   `$XDG_RUNTIME_DIR` and name the ready file inside it. Run `qs -p
   <package>/share/silere-shell/lock.qml` under `setsid` (its own process
   group) and `systemd-cat -t silere-lock`, in the background, with the lock
   descriptor closed and with `SILERE_LOCK_WRAPPER=1`, `SILERE_LOCK_READY_FILE`,
   `NO_COLOR=1`, `QS_DISABLE_CRASH_HANDLER=1`, and `PATH` set to the shell's
   own curated path (`silereShellPath` in `silere.nix`, exported through
   `local.hyprland.commands`), so `FontScan` finds `fc-list` and the lock's
   probes agree with the bar's. Quickshell's crash handler is compiled into the
   pinned `qs`: on a crash it forks a reporter window that lives until closed,
   and a crash more than 10s after launch re-`execve`s a relaunch under the
   same PID, so the wrapper would never see the exit. It has to be an
   environment variable, because the handler starts before `lock.qml`'s pragmas
   apply.
4. **Confirm it.** Wait up to 3s (30 iterations) for the ready file. If the
   process exits first, or the file never appears, stop it (TERM, up to 1s,
   KILL), kill what is left of its process group, `wait` for it to be gone, and
   only then start hyprlock (step 6).
   Hyprland ignores a new lock client while an earlier lock request is still
   unconfirmed, so starting hyprlock before the old process has died could drop
   its request and leave a lockdead screen nobody can clear. `hyprctl locked` is
   no substitute for the ready file: it turns true as soon as any client
   requests a lock, before a frame, and stays true after that client dies.
5. **Wait for the end.** Once ready, wait for the process and capture its
   status; then kill what is left of its process group. The wait polls rather
   than blocks: a client still running once the session has read unlocked on
   two checks a second apart is stopped and counts as an unlock, since it
   would otherwise hold the flock and silently turn every later lock off. Exit 0 means the user
   unlocked; confirm it by polling `hyprctl locked` for up to 1s (unlock clears
   it at once), and if the session still reads locked, fall back to hyprlock as
   in step 4. Any other exit, including a crash while locked (Hyprland then
   shows its lockdead screen), falls back the same way, and hyprlock takes over
   the dead lock because restore is on. A lock request that arrives while a
   lock is ending finds the flock held and the session reading unlocked, so it
   waits up to 5s for the flock and then locks, instead of being dropped.
6. **Stay with hyprlock.** hyprlock runs as a supervised child under
   `systemd-cat -t silere-lock` (bare when the journal does not answer a probe,
   since `systemd-cat` exits without running its command when it cannot open
   a stream). The wrapper waits as in step 5. A hyprlock that ends without an
   unlock (non-zero, or the session still reads locked) is started again a
   second later, up to five times, so a crash leaves the lockdead screen for a
   second, not until the next lock request. One that never makes its lock
   request within about 10s is stopped and counted as a failed start. Until it
   is first seen locked the session is checked five times a second, so a quick
   unlock is not mistaken for a client that never locked.

`hyprctl locked` runs under `timeout 2`, because a hung compositor must not
hang the wrapper; a missed answer fails safe (unlocked before a lock starts,
still locked after one ends), and only an answered "false" ever stops a client.
Every log write and the journal probe get `timeout 1`, so a hung journal cannot
hold up a lock. The wrapper's own log lines fall back to stderr, and a failed or
broken write there never aborts it.

Supporting settings, all in nixos-config:

- `misc:allow_session_lock_restore`, so hyprlock can take over after the lock
  process dies. Hyprland keeps the session locked when a lock client dies, but
  refuses a new client without this.
- `inhibit_sleep = 3` in hypridle for both lock modes: mode 2 only waits for
  lock-notify when `lock_cmd` mentions hyprlock, and the wrapper's name does
  not. Hyprland sends lock-notify for any session-lock client, and the session
  being locked releases the inhibitor.
- logind's `InhibitDelayMaxSec` raised to about 10s
  (`services.logind.settings.Login.InhibitDelayMaxSec`). hypridle's sleep
  inhibitor is a delay inhibitor capped by it (systemd's default is 5s), and a
  cold Quickshell start, plus the 3s confirmation window and a hyprlock
  fallback, can exceed 5s.
- In `"hyprlock"` mode the wrapper does steps 1, 2 and 6, so restore never lets
  two hyprlocks meet there either.

## Power on the lock

The lock owns its countdown: the same 60s as the desktop card, Enter to run now,
Esc to cancel, rendered through the card body extracted in step 1, so the two
look identical. `PowerActionState` is the shell's, not the lock process's, and
it refuses popups while idle anyway, which is exactly when hypridle locks.

It runs plain `systemctl suspend`, `systemctl reboot` and `systemctl poweroff`,
not `Settings.rebootCommand`/`poweroffCommand`: those go through
`HyprDispatch.sessionEndCommand` to hyprshutdown, which closes every layer client
and lets an app with unsaved work block shutdown behind the lock, where its
prompt cannot be reached. The command runs in a `Process` whose exit code feeds
the card; a failure shows on the card with the matching title ("Reboot failed",
"Shut down failed") while the screen stays locked. The divergence from the
desktop card goes in the ledger.

The command carries `--no-ask-password`: polkit's prompt would open on the
desktop behind the lock, where nobody can answer it. A command still running
after 30s, or a reboot or power off still not under way a minute after logind
accepted it, ends on the failure card, so the field is never out of reach for
long.

Only a lock the wrapper started reaches systemd: `lock.qml` sets
`LockPower.live`, which defaults to false. A preview or sandboxed run executes
`true` in its place, or `false` when `SILERE_LOCK_PREVIEW_POWER=fail`, so the
dev loop can show every state of the card without suspending the machine.

## Logging

Every lock is traceable in one place: `journalctl --user -t silere-lock`. The
wrapper runs the lock process under `systemd-cat -t silere-lock` and logs its
own decisions there too. Every lock arrives through hypridle, so one environment
applies to all of them.

Checked in the journal on 2026-10-26: Quickshell 0.3.1 writes every line to
stdout at one priority, with ANSI colour codes unless `NO_COLOR` is set, and
prints the category in each line (`WARN scene: …`). So:

- **The wrapper** logs with real priorities through `systemd-cat -p`: a lock
  already running (info), the ready file seen (info), the exit code (info for 0,
  warning otherwise), a session still locked after exit 0 (warning), and every
  fallback to hyprlock with its reason (warning).
  `journalctl --user -t silere-lock -p warning` lists every fallback.
- **The lock process** logs through a `LoggingCategory` named `silere.lock` with
  `defaultLogLevel: LoggingCategory.Info` (QML categories default to Debug,
  which would log PAM prompt text), in the existing `silere-shell:` voice: lock
  created and confirmed (`secure`), each output's surface, PAM started and its
  result, unlock, `finished`, a refusal to lock and why, the exit code chosen,
  power actions with their exit codes, font fallback, and wallpaper load
  errors. Its lines all arrive at one priority; filter with `-g 'WARN'` for its
  warnings.
- **Debug detail** (PAM message text, timings) is off by default. Set
  `QT_LOGGING_RULES="silere.lock.debug=true"` with `systemctl --user
  set-environment` and restart hypridle; the wrapper passes it through, and
  Quickshell applies `QT_LOGGING_RULES` to categories outside its own.
- **Never logged:** the typed password, its length, or any PAM response.

The README gains a short "Debugging the lock" section with these commands, plus
`journalctl --user -u hypridle.service` for the requests that started a lock.

## Plan

One commit per step. Fork commits follow the `type(scope): subject` style in
`git log`. Each fork step that creates or changes a divergence from upstream
updates `docs/upstream-divergences.md` in the same commit, as the fork's
AGENTS.md requires. Settings keys cross repositories, so step 2 lands together
with step 9, and nixos-config's steps 9 to 11 reach its main branch only
together with the re-lock to a pushed `custom-branch` tip that contains the
fork's steps. In the other order, the packaged shell lacks the new keys and
`lockPowerButton` reads as undefined, which is false.

### silere-shell

1. Extract the body of `modules/power/PowerActionCard.qml` into a reusable item,
   so the desktop card and the lock both render it. No behaviour change.
2. Add the four settings: properties and `_schema` entries in `ShellSettings`,
   the matching lines in `config/GeneratedDefaults.qml` (the settings contract
   counts them there too), and the two rows on the Interface page (steps 5 to 7
   add the reads), with the upstream-neutral defaults above. Add
   `pkgs.jetbrains-mono` to the dev shell's fonts in `flake.nix`, so `check.sh`
   measures the real default face.
3. The read-only settings mode (`SILERE_SETTINGS_READ_ONLY=1`) and its gates
   in `PersistedFile.flush`, `ConfigStore` and
   `ShellSettings._backupSettingsText`.
4. `lock.qml` and `modules/lock/` (with its `qmldir`): the process lifecycle,
   the `allowed` gate and preview mode, PAM, the ready file, exit codes, hot
   reload off, the read-only pragma, the `silere.lock` logging category, and the
   singleton audit. `Quickshell.Services.Pam` joins `SILERE_REQUIRED_QML_MODULES`
   in `scripts/lib/qml-modules.sh`, and `lock.qml` joins the path lists in
   `ci-lint.sh` that name `shell.qml` (about 22 of them), or the gates skip it.
5. The lock's layout, iterated in preview mode: background, clock, date and
   battery with the runtime font alignment and the capped font settle, the
   field and its messages, Caps Lock, the clock-only secondary outputs,
   keyboard focus after resume, and keyboard handling within `ci-lint.sh`'s
   keyboard rule (`Shortcut` for Esc and Enter outside the password field, as
   `PowerActionCard` does).
6. Power on the lock: the three-option card and the countdown running plain
   `systemctl`.
7. Menu integration: `Settings.lockCommand` runs `ShellSettings.lockCommand`
   when it is set, so the menu's Lock entries (`modules/menu/HomePage.qml`,
   `modules/menu/PowerRailContent.qml`) lock the same way everything else does.
   The Maintenance page's "Screen lock hidden until hyprlock is installed" row
   and `scripts/test-notification-stack.sh`'s `pgrep hyprlock` detection learn
   about the new lock.
8. Docs: the README's feature list and its "Debugging the lock" section.

### nixos-config

9. With step 2: the four options in `silere.nix` and their render lines,
   keeping the settings contract equal. `lockFontFamily` defaults to "JetBrains
   Mono", `lockWallpaper` renders `local.hyprland.wallpaper`, and `lockCommand`
   renders "" until step 10. Also `pkgs.jetbrains-mono` in
   `modules/home-manager/fontconfig.nix` and `security.pam.services.silere-lock`
   in `modules/nixos/hyprland.nix`, next to the `hyprlock` entry.
10. Lock safety, in one commit because each part needs the others: the
    `silere-lock` wrapper in its `"hyprlock"` form (scope, flock, hyprlock
    check), used by hypridle's `lock_cmd`; `lockCommand` rendered as `loginctl
    lock-session`; `silereShellPath` exported through `local.hyprland.commands`;
    `misc:allow_session_lock_restore`; `inhibit_sleep = 3`; logind's
    `InhibitDelayMaxSec`. Rewrite the `lock_cmd` and `inhibit_sleep` comments in
    `hypridle.nix`, including "Hyprland rejects duplicate session-lock clients",
    which stops being true once restore is on.
11. `local.hyprland.lockScreen`, `"hyprlock"` or `"follow-shell"`, defaulting to
    `"hyprlock"` until the new lock is proven, so rollback is one line.
    `"follow-shell"` gives the wrapper its steps 3 to 5. Add `lock.qml` to the
    files `silere.nix` copies into the package (today only `shell.qml` and its
    folders); it exists only from fork step 4, so it cannot go in earlier, and
    without it `qs` cannot open the lock and every lock falls back to hyprlock.
    The Hyprland profile README's lock section documents the switch and the
    journal commands.
12. After the lock is proven on the NixOS install: make `"follow-shell"` the
    only behaviour and remove the `lockScreen` switch, in its own commit.
    hyprlock, its PAM service and its wallpaper copy stay as the fallback.
    Update the README lines that describe hyprlock as the lock screen.

## Manual QA

No new automated tests or probes. Once the steps are in, the lock gets a manual
QA checklist, written at that point and run by hand in the real session on the
NixOS install, with hyprlock as the fallback and a spare TTY as the way out.

Three things the checklist depends on: steps 9 and 10 must be built and
switched to first (`PamContext.start()` fails without a message when
`/etc/pam.d/silere-lock` is missing, and the fallback needs restore on);
nixos-config builds the fork with a build-time override such as
`--override-input silere-shell path:/home/olaolu/Desktop/dev/silere-shell`,
never a committed re-lock to an unpushed branch; and `journalctl --user -t
silere-lock` is how a failed check gets diagnosed.

The repository gates in AGENTS.md still apply to every commit, as they do to
all fork work.

## Open questions

- **Caps Lock state.** Resolved in step 5: the main keyboard's `capsLock` in
  `hyprctl devices -j`. It is Hyprland's own xkb state, the one the typed text
  gets, where the `/sys/class/leds` LED exists only on keyboards that have one
  and is a copy Hyprland pushes to each device. Never polled: the lock asks at
  start, on every Caps Lock press it receives, and whenever a surface takes the
  keyboard (resume, hotplug). Niri has no such query, so the chip stays hidden
  there.
- **The focused output while locked.** Resolved in step 5. Hyprland 0.55.4's
  `mouseMoveUnified` calls `rawMonitorFocus` before its session-lock branch,
  which posts `focusedmon` and then hands that output's lock surface the
  keyboard (read in the source, not seen in a live lock). The field goes to the
  surface whose window is active, since that is where typing lands; until one
  is, Hyprland's focused monitor; else the first output.
- **logind option.** `services.logind.settings.Login.InhibitDelayMaxSec` was
  seen in store copies of the 26.05 module; confirm it against the pinned
  nixpkgs in step 10.
- **Menu Lock while hypridle is down.** `loginctl lock-session` does nothing
  then (hypridle restarts after 10s). Super+L already shares that dependency;
  decide in step 10 whether `lockCommand` adds a guard (`systemctl --user
  is-active -q hypridle.service || exec silere-lock`).
- **Lockout.** The lockout message shows only when PAM returns `MaxTries`. NixOS
  sets no attempt limit by default, so it stays hidden unless `pam_faillock` is
  enabled.
- **Scaling.** Resolved in step 5: with `ShellSettings.uiScale`, like the rest
  of the shell's type, never with the output's height. The design's sizes and
  gaps are multiplied by it (`LockState.px`), row heights come from
  `Metrics.rowHeightFor`, and the 80px corner margins stay fixed, as the other
  surfaces' frames do.
