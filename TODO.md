# TODO

Deferred work worth revisiting. Each entry records why it waited, so it can be
picked up without redoing the analysis.

## Notification actions in history

Keep a notification's action buttons usable from the Recent page while the
sending app still holds it, as GNOME's message list does.

Deferred on 2026-10-06 because it is not a small change. A popup that times
out expires its notification (`_dismissObject` in `services/Notifications.qml`),
so a history row has no live object whose actions could be invoked. Matching
GNOME means:

- keeping a timed-out notification tracked, hidden but open, and making that
  set hold up across the active cap, the DND, fullscreen and popups-off paths,
  and reloads (`keepOnReload` and the live-id map);
- linking each history row to its live object, so that removing a row or
  clearing history closes the notification and a close from the sender
  updates the row;
- adding action buttons to the `RecentPage` rows;
- accepting that apps then see their notifications as still open, which
  changes how some of them count or replace notifications.

Saved history never carries actions. Actions are callbacks to the sender, and
they stop working once the notification closes or the session ends.

## VPN address after a same-uuid reconnect

Close the two gaps left in the stale-address reread (`_vpnAddressStale` in
`services/Network.qml`). Both affect only a VPN profile that keeps its uuid
and name across a reconnect, such as an OpenVPN roam. Proton makes a new
profile, and so a new uuid, for every connection. The menu row heals both on
open, because the Home page rereads the address; until then only the bar
pill's hover text shows the old address.

Deferred on 2026-10-15 because neither reaches this machine's VPN, and each
fix to the reread had turned up a smaller edge in its own new state. The gaps:

- without `ip`, a tunnel that is gone at one 5 s read of `/proc/net/dev`
  and back at the next has no earlier counter to compare, so
  `_countersRestarted` never sees it and the address is never marked stale.
  With the `ip` watcher up, the deletion marks it and, while a VPN is up,
  holds the mark for 9 s and rereads the address then, so a tunnel back
  within those 9 s, or an address handed out within them, reaches the bar
  (probed with the tunnel away 4.2 s and 8 s, and the address 4.5 s to
  8.5 s late). A tunnel away longer, or an address handed out later, while
  NetworkManager keeps listing the uuid with the old address, still does
  not (probed at 10 s and 9.5 s). Marking it stale on any change to the
  interface list would cover a tunnel away for longer, with or without
  `ip`; the 5 s poll missed an address handed out that late as well;
- the mark clears after the settle listing even when a read was still in
  flight, so a read that started before the rebuild can settle on the old
  address. A failed read marks it again. Clearing it only while no read is
  running would cover the rest.

The logic probe checks only that a rebuild sets the mark. The reread itself
runs in `_vpnProc`'s exit handler; `scripts/test-network-links.sh` drives it
through a stand-in `nmcli`, with the watcher up only.

## Lock screen step 12

Make the shell's lock the only lock. Step 12 of the
[lock screen plan](docs/lock-screen-plan.md) removes nixos-config's
`local.hyprland.lockScreen` switch, so `"follow-shell"` is the only behaviour,
and updates the README lines that describe hyprlock as the lock screen.
hyprlock, its PAM service and its wallpaper copy stay as the fallback.

Deferred on 2026-10-27 because it waits until the lock is proven on the NixOS
install, which the [manual QA checklist](docs/lock-screen-qa.md) checks. Until
then the switch keeps rollback to one line.

## JetBrains Mono in the dev shell

Add `pkgs.jetbrains-mono` to the dev shell's fonts in `flake.nix`, so
`check.sh` measures the lock font's real default face (step 2 of the
[lock screen plan](docs/lock-screen-plan.md)).

Deferred on 2026-10-27 because at the fork's pinned nixpkgs that package builds
from source and one of its fixed-output inputs fails its hash, so it waits for
a nixpkgs bump.

## One shared setup for the probe runners

Move the setup that every `scripts/test-*.sh` runner repeats into one helper in
`scripts/probe-lib.sh`: the scratch directories with their cleanup trap
installed first, the private config, state, cache and runtime directories, the
offscreen launch with its environment, the wait for the done line, and the
error scan. Each runner then keeps only what is its own: its probe, its
stand-in tools and any extra checks. This was finding TEST-8 of the 2026-11-10
review.

Of the 36 runners, 32 relaunch on a private session bus, set the private
directories and define their own cleanup, and 28 launch Quickshell offscreen,
each by hand. Every setup bug that review turned up came from a copy that had
drifted: two runners with no private config directory, three that made their
temporary directories before installing the trap, and one whose probe reached
the machine's own Wi-Fi through the system bus. Those are fixed one by one, and
`_probe_private_bus` now withholds the system bus from every runner that uses
it.

Still outside that: `test-qml-headless.sh` does not go through
`_probe_private_bus`, and the startup smoke cases in `check.sh` start the real
shell on a session bus of their own and still see the system bus. The helper
should cover both, or say why not.

Deferred on 2026-11-11 because nothing is broken for lack of it and it touches
every runner at once. It costs no merge surface, since all but one runner are
the fork's own. The runners differ in small ways, so convert them a few at a
time and run the full check after each batch.
