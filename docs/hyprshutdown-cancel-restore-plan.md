# hyprshutdown cancel restore plan

Status: proposed, not implemented. Recorded on October 2, 2026, so the
reasoning survives until the maintainer decides whether to build it.

## The gap

Log out, Reboot and Power off on Hyprland hand off to hyprshutdown through
`scripts/hypr-session-end.sh`. hyprshutdown closes every app as soon as it
starts, before its own screen appears. It asks windows to close, and it sends
SIGTERM to every layer client and every process Hyprland launched. Its Cancel
stops the wait. It does not bring anything back.

The power rail's countdown card is the safe cancel point, because nothing has
run before it ends. hyprshutdown's Cancel is still reachable afterwards, when an
app holds up the wait screen, and so is a failed run. In both cases the script
restarts the shell's own unit so that the bar returns and can report the
failure. Nothing restarts the other session services hyprshutdown stopped. On
the maintainer's machine, those are:

- `hypr-shell-awww.service`, the wallpaper daemon
- `hypr-shell-media-idle-inhibit.service`

Both use `Restart=on-failure`. systemd counts death by SIGTERM (and SIGHUP,
SIGINT, SIGPIPE) as a clean exit, so neither restarts. `Restart=always` would be
wrong. During a real log out it would restart them while hyprshutdown is still
closing everything.

The wallpaper has a second problem. `hypr-shell-wallpaper-restore.service` is a
oneshot with `RemainAfterExit=true` that only `Requires=` the daemon.
`Requires=` passes on stop jobs, not a process dying, so the restore stays
`active (exited)` and never runs again. A restarted `awww-daemon` starts with
no wallpaper, so the background stays blank.

## Proposed fix

1. **Fork, `scripts/hypr-session-end.sh`:** after a cancel or a failure, start
   the shell unit's session target instead of the shell unit alone. Read the
   target from the unit's `PartOf=` (`systemctl --user show -p PartOf`), so the
   script hardcodes no nixos-config names. Fall back to starting the shell unit
   when it has no `PartOf=`. Starting the target brings back every stopped unit
   it wants: the shell, the wallpaper daemon and the idle inhibitor.
2. **nixos-config, `wallpaper.nix`:** change the restore unit's
   `Requires=hypr-shell-awww.service` to `BindsTo=`. `BindsTo=` also reacts to
   the daemon's process dying, so the restore goes inactive with it and runs
   again when the target starts. The once-per-session reasoning in that unit's
   comment still holds.

## Verify before building

- Confirm that starting an already-active target starts its stopped `Wants=`
  units. Test with throwaway user units, as the cgroup kill behaviour was
  tested, before relying on it.
- Confirm that `BindsTo=` deactivates the oneshot when the daemon is SIGTERMed
  and that the target start re-runs it.

## Out of scope

Windows that hyprshutdown already closed cannot come back. This plan only gets
the session working again after a cancel.
