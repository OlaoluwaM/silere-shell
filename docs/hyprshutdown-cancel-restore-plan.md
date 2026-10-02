# hyprshutdown cancel restore plan

Status: implemented and validated on October 2, 2026. The fork half is in
`scripts/hypr-session-end.sh`; the nixos-config half is the `BindsTo=` change
below, which the maintainer commits there.

## The gap

Log out, Reboot and Power off on Hyprland hand off to hyprshutdown through
`scripts/hypr-session-end.sh`. hyprshutdown closes every app as soon as it
starts, before its own screen appears. It asks windows to close, and it sends
SIGTERM to every layer client and every process Hyprland launched. Its Cancel
stops the wait. It does not bring anything back.

The power rail's countdown card is the safe cancel point, because nothing has
run before it ends. hyprshutdown's Cancel is still reachable afterwards, when an
app holds up the wait screen, and so is a failed run. Session services that
hyprshutdown stopped stay down after either, because systemd counts death by
SIGTERM (and SIGHUP, SIGINT, SIGPIPE) as a clean exit and `Restart=on-failure`
does not fire. On the maintainer's machine that includes the shell itself, the
wallpaper daemon (`hypr-shell-awww.service`) and the idle inhibitor
(`hypr-shell-media-idle-inhibit.service`). `Restart=always` would be wrong:
during a real log out it would restart them while hyprshutdown is still closing
everything.

The wallpaper has a second problem. `hypr-shell-wallpaper-restore.service` is a
oneshot with `RemainAfterExit=true` that only `Requires=` the daemon.
`Requires=` passes on stop jobs, not a process dying, so the restore stays
`active (exited)` and never runs again. A restarted `awww-daemon` starts with
no wallpaper, so the background stays blank.

## What was built

1. **Fork, `scripts/hypr-session-end.sh`:** before hyprshutdown starts, the
   launcher records the shell's unit and every unit its `PartOf=` target wants
   that is running at that moment. After a cancel or a failure, the transient
   unit starts the recorded units that have stopped. Recording first matters:
   starting the whole target would also start units stopped on purpose, such as
   `hyprsunset.service` when night light is off. The script hardcodes no
   nixos-config unit names.
2. **nixos-config, `wallpaper.nix`:** the restore unit's
   `Requires=hypr-shell-awww.service` becomes `BindsTo=`. `BindsTo=` also reacts
   to the daemon's process dying, so the restore goes inactive with it, gets
   recorded as stopped, and runs again when it is started. The once-per-session
   reasoning in that unit's comment still holds.

## Validation

Throwaway user units under `$XDG_RUNTIME_DIR/systemd/user`, removed afterwards:

- A SIGTERMed `Restart=on-failure` daemon stays down.
- With `Requires=`, the oneshot stays active and does not run again; with
  `BindsTo=`, it goes inactive with the daemon and runs again on start.
- Starting an already-active target starts its stopped wants.
- The script's own restore, with a stub hyprshutdown that cancels after
  SIGTERMing a fake shell and daemon, brought both back and re-ran the bound
  oneshot, and left a deliberately stopped wanted unit stopped.

## Out of scope

Windows that hyprshutdown already closed cannot come back. This only gets the
session working again after a cancel.
