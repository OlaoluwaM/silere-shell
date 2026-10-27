# Lock screen: manual QA

The hand-run checklist for the lock screen in
[lock-screen-plan.md](lock-screen-plan.md), run in the real Hyprland session on
the NixOS install. Tick each box as it passes. When one fails, note what
happened and the matching lines of `journalctl --user -t silere-lock`, then stop
and report it before moving on.

## Before you start

- [ ] Open work is saved. A few checks can end in a reboot, and the last-resort
  escape ends the graphical session.
- [ ] A spare TTY is logged in (Ctrl+Alt+F3) as your own user, as the way out if
  a lock ever gets stuck. Read "Escape hatches" below first, and check that
  `hyprctl instances` on that TTY lists your session.
- [ ] Back up the shell's settings, so a lock that wrote them by mistake can be
  undone: `cp -a ~/.config/silere-shell ~/silere-shell-config.qa-backup`.
- [ ] Note the current system generation (`nixos-rebuild list-generations |
  tail -n 1`), so you know what `--rollback` returns to.
- [ ] Both repositories are on their `lock-screen` branches with clean trees.
- [ ] nixos-config is built against the local fork, never a re-lock to an
  unpushed branch:

  ```sh
  cd ~/nixos-config
  sudo nixos-rebuild switch --flake .#boreas \
    --override-input silere-shell path:/home/olaolu/Desktop/dev/silere-shell
  ```

- [ ] `/etc/pam.d/silere-lock` exists, and `hyprctl getoption
  misc:allow_session_lock_restore` reports `1`.
- [ ] `grep InhibitDelayMaxSec /etc/systemd/logind.conf` shows `10`.
- [ ] The silere-shell service restarted onto the new build (`systemctl --user
  status silere-shell.service` shows a start time after the switch).

## Escape hatches

All of these run on the spare TTY (Ctrl+Alt+F3), then Ctrl+Alt+F1 or F2 back to
the graphical session. Try them in this order; each is more drastic than the
last.

1. **The shell's lock will not take the password** (a wrong PAM setup, a field
   with no focus, keys going nowhere): end it, and the wrapper hands the session
   to hyprlock within about a second.

   ```sh
   pkill -KILL -f 'lock\.qml'
   ```

   If hyprlock does not appear, the wrapper is gone too; use 2.

2. **Hyprland's lockdead screen, or a lock with no client at all** (the screen
   says the lock client died): start hyprlock yourself. Restore is on, so it
   takes over the dead lock.

   ```sh
   hyprctl --instance 0 dispatch exec hyprlock
   ```

3. **Screens stay black after resume:** turn the outputs back on.

   ```sh
   hyprctl --instance 0 dispatch dpms on
   ```

4. **The session keeps re-locking**, or a request never seems to arrive: stop
   idle locking, and end any wrapper still holding the lock guard.

   ```sh
   systemctl --user stop hypridle.service
   pkill -f '/bin/silere-lock'
   ```

   `systemctl --user start hypridle.service` brings idle locking back.
5. **Locking is broken in the new build:** go back to the previous system
   generation, which also restores the previous Home Manager generation and its
   hyprlock setup, then reboot to be sure nothing of the new build is running.

   ```sh
   sudo nixos-rebuild switch --rollback
   ```

   If the system will not get that far, pick the previous generation in the boot
   menu.
6. **Nothing above unlocks the session (last resort; open windows are lost):**
   end the Hyprland session and log in again.

   ```sh
   hyprctl --instance 0 dispatch exit
   ```

   If Hyprland does not answer, `loginctl terminate-user "$USER"` from the TTY
   ends every session of yours, including that one.
7. **The TTY cannot be reached** (Ctrl+Alt+F3 does nothing): hold the power
   button. Phase 1 checks that VT switching works while locked, so this should
   never be needed.

If settings changed while locked, restore them from the backup:
`rm -rf ~/.config/silere-shell && cp -a ~/silere-shell-config.qa-backup
~/.config/silere-shell`, then `systemctl --user restart silere-shell.service`.

## Phase 1: hyprlock mode (the default)

`local.hyprland.lockScreen` is unset, so it is `"hyprlock"`. This checks the
wrapper before the new lock is in play.

- [ ] Super+L locks with hyprlock; unlocking works.
- [ ] While hyprlock is up, Ctrl+Alt+F3 reaches the spare TTY and Ctrl+Alt+F1 or
  F2 comes back to the lock. Every escape hatch depends on this, so do not go
  on to Phase 2 if it fails.
- [ ] `journalctl --user -t silere-lock -n 20` shows `locking with hyprlock` and
  `hyprlock exited after an unlock`.
- [ ] Super+L twice in quick succession: one hyprlock (`pgrep -c -x hyprlock`
  reads 1 while locked), and the second request logs `a lock is already
  running; nothing to do`.
- [ ] The menu's Lock (Home page, then the power rail) locks with hyprlock and
  logs under the same tag.
- [ ] Idle lock: wait out the idle timer; hyprlock appears.
- [ ] Lid close or `systemctl suspend`: the session is locked on resume, with no
  desktop visible first.

## Phase 2: the shell's own lock

Set `local.hyprland.lockScreen = "follow-shell";` (for example beside
`local.hyprland.enable` in `modules/home-manager/desktop.nix`; leave it
uncommitted for now) and rebuild with the same command. For the first lock, have
the spare TTY one keystroke away: if the new lock will not take your password,
escape hatch 1 hands the session to hyprlock.

### Look and layout

- [ ] Super+L shows the new lock on every output within a second or so.
- [ ] Primary output: clock top-left with the date under it, their left edges
  lined up; battery top-right, its digits level with the top of the clock; user
  name over the password field bottom-left; power button bottom-right, level
  with the field.
- [ ] Other outputs show the clock alone.
- [ ] The background is the current wallpaper, blurred and dimmed.
- [ ] Battery reads `· charging` on AC; below the low threshold it reads `· plug
  in` in the error colour.
- [ ] The clock follows the 12/24-hour setting and never shows seconds.

### Unlocking

- [ ] A wrong password shows `Wrong password · 1 attempt`, shakes the field, and
  clears it; a second shows `2 attempts`.
- [ ] The right password fades the lock out and unlocks; the journal shows `the
  shell's lock exited with status 0`.
- [ ] Esc clears typed text at once; typed text clears after 10 s idle.
- [ ] Caps Lock on shows the chip in the field; off hides it. Also lock with
  Caps Lock already on: the chip shows from the start.
- [ ] Typing while the pointer is on another output still lands in the field.
- [ ] Moving the pointer to another output moves the field there (the focused
  output is the primary).

### Suspend and resume

- [ ] Lock, then suspend: on resume the lock is up, the field has focus, and the
  clock shows the current time at once.
- [ ] Lid close from an unlocked desktop: locked before sleep, nothing of the
  desktop visible on resume.

### Power

- [ ] The power button opens the card with Suspend, Reboot and Power off; Esc
  and a tap outside both close it, and the field takes focus again.
- [ ] Reboot starts the 60 s countdown; Cancel and Esc both stop it. (Let one
  run to the end only if you are ready to reboot. Once it runs there is no way
  back.)
- [ ] A double-click on the Power off tile opens the countdown but does not
  confirm it. Have your other hand on Esc: if it does confirm, the machine
  powers off.
- [ ] Suspend runs at once, and the machine wakes to the lock.
- [ ] While a password is being checked, the power button is disabled.
- [ ] With `lockPowerButton` off (Interface page, Lock screen section), the
  button is gone.

### Failure and fallback

- [ ] From the TTY, while the new lock is up: `pkill -KILL -f 'lock\.qml'`.
  Within about a second hyprlock takes over, and `journalctl --user -t
  silere-lock -p warning` shows the exit and the fallback. Unlock with hyprlock.
- [ ] From the TTY, while locked: `systemctl --user restart hypridle`. The lock
  stays up (it runs in its own scope).
- [ ] Unlock, then press Super+L again straight away: it locks again.
- [ ] The menu's Lock locks with the new lock, and its lines appear under `-t
  silere-lock` (not under `-u hypridle.service`).

### Logging

- [ ] `journalctl --user -t silere-lock` shows each lock from request to unlock,
  with no colour codes.
- [ ] Nothing in it contains the password, its length, or PAM's prompt text
  (`journalctl --user -t silere-lock -g 'Password'` finds nothing).
- [ ] Debug: `systemctl --user set-environment
  QT_LOGGING_RULES="silere.lock.debug=true"`, restart hypridle, Super+L: debug
  lines appear. Then `systemctl --user unset-environment QT_LOGGING_RULES` and
  another hypridle restart turn them off; don't leave debug on, since it logs
  PAM's message text.

### Settings and font

- [ ] The lock writes nothing: `stat ~/.config/silere-shell/*` before and after
  a lock shows the same modification times.
- [ ] Interface page, Lock screen, Font: pick another family; the next lock uses
  it, and the clock, date and battery still line up.
- [ ] A family that is not installed (set by hand in `settings.json`) falls
  back to JetBrains Mono, and the journal logs the fallback.
- [ ] `wallpaper-set` a new image; the next lock shows it.

## Phase 3: rollback

- [ ] Remove the `lockScreen` line, rebuild: Super+L is hyprlock again. Rollback
  is that one line.
- [ ] Remove the settings backup once you're satisfied: `rm -rf
  ~/silere-shell-config.qa-backup`.

## After it passes

1. Decide whether to keep `"follow-shell"` set for daily use until step 12.
2. Bring `lock-screen` into `custom-branch` and push it, then merge
   nixos-config's `lock-screen` branch and re-lock it in the same rebuild, as
   README.md's "Pinning from nixos-config" describes. The new settings keys tie
   the two together.
3. Step 12 of the plan, once the lock has proven itself.
