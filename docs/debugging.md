# Debugging

## Finding the shell's logs

The deployed shell is the user unit `silere-shell.service`, so
`journalctl --user -u silere-shell` shows everything it prints, Qt's and
Quickshell's own messages included. `journalctl --user -u silere-shell -g
'silere[-.]'` keeps only the shell's own lines: each names a `silere.` category
or starts with `silere-shell: `. The lock, network, caffeine and night light
lines do both, so `-g silere-shell` alone finds those; the notification
history's lines start with `history:` or `grouping:` under their category, and
the delivery gate's with `delivery:`. A
line reads `INFO silere.network: silere-shell: link watcher up`: the level,
the category, then the message.

Each area logs under a category of its own:

- `silere.lock`: the lock screen, below.
- `silere.notifications`: the history, the menu's grouping of it, and which
  notifications were held back or let through.
- `silere.network`: the VPN indicator and the kernel link watcher.
- `silere.caffeine`: the idle inhibitor unit and its stop timer.
- `silere.nightlight`: the sunsetr unit, its status stream and its config.

`journalctl --user -u silere-shell -g 'silere\.network'` shows one category.
Warnings mean something failed or timed out, Info a state change someone may
ask about later, and Debug the detail of single events. Debug is off by
default. To turn one category's Debug lines on, run `systemctl --user
set-environment QT_LOGGING_RULES="silere.network.debug=true"` and restart
`silere-shell.service`; unset it and restart again to turn them off. A dev
instance (`nix develop . --command qs -p shell.qml`) prints the same lines to
its terminal, and `QT_LOGGING_RULES=silere.network.debug=true` in front of the
command turns Debug on there. The lock logs under its own journal tag as well,
which the next section covers.

## Debugging the lock

Every lock goes through nixos-config's `silere-lock` wrapper, which logs its
own decisions and the lock process's output under one journal tag:

- `journalctl --user -t silere-lock` shows each lock: the wrapper's decisions,
  the lock process's `silere.lock` lines, and hyprlock's output after a
  fallback.
- `journalctl --user -t silere-lock -p warning` lists only the wrapper's
  warnings: every fallback to hyprlock, with its reason, and every exit other
  than an unlock. The lock process's own lines all arrive at one priority, so
  filter those with `-g WARN`.
- `journalctl --user -u hypridle.service` shows the requests that reached the
  wrapper through hypridle (idle, Super+L, suspend). The menu's Lock asks
  Hyprland to run the wrapper instead, so those requests show only under the
  `silere-lock` tag.

The lock's exit status says how it ended: 0 the user unlocked, 1 the
compositor has no session-lock support, 2 the lock ended without an unlock,
3 it refused to lock because the wrapper did not start it or it runs
sandboxed, 255 a QML load error. Anything but 0 hands the session to hyprlock.

Debug detail (PAM message text, timings) is off by default. To turn it on, run
`systemctl --user set-environment QT_LOGGING_RULES="silere.lock.debug=true"` and
restart hypridle, which starts the wrapper for idle, Super+L and suspend; lock
with Super+L to see them. The menu's Lock starts the wrapper through Hyprland
instead, in Hyprland's environment, which that setting never reaches. `systemctl
--user unset-environment QT_LOGGING_RULES` and another hypridle restart turn it
off. The typed password, its length and PAM's responses are never logged.

To work on the layout, preview it in a window instead of locking:
`SILERE_LOCK_PREVIEW=1 nix develop . --command qs -p lock.qml`. Started any
other way outside the wrapper, `lock.qml` refuses to lock and exits 3.

## Debugging notification history

The history and the menu's grouping of it log under the `silere.notifications`
category, which `journalctl --user -u silere-shell -g silere.notifications`
shows. Removing one row or one run logs four lines: the row and the run
the delegate thought it held, the rows the model actually removed, and the
page's runs before and after, each as app, length, and whether a stack stands
open or folded. The page header's Clear logs one line with the row count.
A row lost from the model shows in the removal line; a row only
hidden shows as a run that folded in the after line. A row the list took back
mid-exit, or one left faded once every exit ended, logs as well. Notification
text is never logged.

Updates that replace a row, trims and the grouping's open-state bookkeeping
log at Debug. To see them, run `systemctl --user set-environment
QT_LOGGING_RULES="silere.notifications.debug=true"` and restart
`silere-shell.service`; unset it and restart again to turn them off.

Two more lines come from the start-up and the page. A `notifications.json`
that still carries the `seen` and `times` of an older version logs one Info
line, since that state is ignored and goes at the next save. A grouping that
could not make its row listener logs one Warn, because every read then rebuilds
its table.

## Debugging what DND holds back

The same category says why a notification did or did not pop up. Each one
that arrives while something silences it logs a `delivery:` line at Debug:
`held by DND`, `held by fullscreen` or `held, popups are off`, or `let through
as critical` or `let through as a listed app`. The line ends with the
sender's name and its desktop entry, each quoted, and the notification's id,
never its text.

`dndBypassApps` lists the apps let through, and an entry has to equal one of
those two fields, whatever the case. To find what to list an app by, turn
Debug on as above, have the app notify while DND is on, and read its `held by
DND` line. When the list loads or changes, one Info line gives the entries as
the shell parsed them, trimmed and in lower case, so a list that reads
`(none)` was empty or never arrived.

## Debugging the network watcher

The VPN indicator follows `nmcli`, and the interface list follows kernel link
events read from `ip -o monitor link`; the 5 s poll reads the list whenever
that watcher is down. Warn shows an `nmcli` listing or address read that
failed or timed out, with its exit code, and the watcher losing kernel events
to a receive-buffer overrun. Info shows the VPN indicator turning on or off,
the watcher coming up, exiting with its code, or giving up, and `ip` being
absent. Debug shows each deleted link by name, the fallback that treats every
link as rebuilt and why, each read of the interface list and whether the
cooldown deferred it, the list changing, the VPN address's stale mark being
set and cleared, and the late reread after a deletion. Addresses, SSIDs, VPN
profile names and uuids are never logged.

## Debugging caffeine

Warn shows an `is-active` check that timed out, a step of the toggle chain
that failed, named by its first words (for example `systemctl --user start`),
with its exit code, and an inhibitor list that could not be read, once per run
of failures. Info shows each toggle request (on with its minutes, or off), a
run the `is-active` check found started or ended outside a toggle, and the
inhibitor watcher giving up. Debug shows queued and run reschedules, the
number of idle inhibitors changing, the session going idle and waking, the
inhibitor watcher starting and stopping, each inhibitor change it hears on
the bus, and the stop deadline being set, passing and read back from systemd.
Inhibitor names and command output are never logged.

Every `is-active` line names what asked for the check, in these words:
`startup`, `the tool scan`, `the toggle chain`, `a failed toggle`, `an empty
chain`, `the drift poll`, `the bus signal`, `the watcher starting`, `the wake
from idle`, `the passed deadline`, `the stop timer going`, or `a direct call`
from a probe. The Info
line for a run found ended also says whether the session was
idle. A run that ended on its own is asked for by the bus signal, at the moment
the unit stopped. One asked for by the wake from idle, minutes after the unit's
own stop line in the journal, means the shell slept through the stop and the
pill stayed lit until the next key press.

## Debugging night light

The shell starts and stops `sunsetr.service`, follows the daemon through
`sunsetr status --json --follow`, and reads and writes its config with
`sunsetr get all` and `sunsetr set`. The daemon logs its own fades under
`journalctl --user -u sunsetr`.

Warn shows a check that timed out, a start or stop that failed or timed out, a
config read that failed or gave no transition mode, a config write that
failed, and the tool going missing. A start, stop, config read or config write
that failed carries its exit code and whether it timed out. Info shows each toggle request and how a
keybind toggle was answered, a check that changed the state, the status stream
connecting and being lost, each period change with the period it left and the
one it entered, each config write with its fields and values, and a timezone
switch handing the new zone's location to sunsetr. A location is written by
field name only, never by value. Debug shows each state the
daemon applied, with its period and temperature, the status reader starting
with its restart count or exiting before any state, config writes dropped
because sunsetr went missing, by field name, a timezone switch's location
dropped for the same reason, and the drift poll starting and stopping. Command
output is never logged.

A stream that is lost runs one `is-active` check, since the daemon may have
stopped with its unit. A reader that exits before any state, as it does while
the daemon is not yet listening, checks nothing and logs only at Debug, so a
row that stays blank while night light is on means the stream never
connected: look for the reader's Debug lines, then at the sunsetr unit itself.
A config read that fails before the daemon's first start, which is when sunsetr
writes its config, is retried once the stream connects.
