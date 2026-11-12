# Debugging

## Finding the shell's logs

The deployed shell is the user unit `silere-shell.service`, so
`journalctl --user -u silere-shell` shows everything it prints, Qt's and
Quickshell's own messages included. `journalctl --user -u silere-shell -g
'silere[-.]'` keeps only the shell's own lines: each names a `silere.` category
or starts with `silere-shell: `. The lock, network, caffeine and night light
lines do both, so `-g silere-shell` alone finds those; the notification
history's lines start with `history:` or `grouping:` under their category. A
line reads `INFO silere.network: silere-shell: link watcher up`: the level,
the category, then the message.

Each area logs under a category of its own:

- `silere.lock`: the lock screen, below.
- `silere.notifications`: the history and the menu's grouping of it.
- `silere.network`: the VPN indicator and the kernel link watcher.
- `silere.caffeine`: the idle inhibitor unit and its stop timer.
- `silere.nightlight`: the hyprsunset unit and its temperature pushes.

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

Every `is-active` line names what asked for the check: startup, the tool scan,
a toggle chain, the drift poll, the bus signal, the wake from idle, or the stop
deadline. The Info line for a run found ended also says whether the session was
idle. A run that ended on its own is asked for by the bus signal, at the moment
the unit stopped. One asked for by the wake from idle, minutes after the unit's
own stop line in the journal, means the shell slept through the stop and the
pill stayed lit until the next key press.

## Debugging night light

Warn shows a check that timed out, a start or stop that failed or timed out,
a temperature push that hyprsunset did not accept, and the tool going missing.
Each carries the exit code. Info shows each toggle request and how a keybind
toggle was answered, a check that changed the state, and a start confirmed.
Debug shows temperature pushes, pushes queued behind another, and the drift
poll starting and stopping. Command output is never logged.
