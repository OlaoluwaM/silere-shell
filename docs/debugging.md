# Debugging

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
