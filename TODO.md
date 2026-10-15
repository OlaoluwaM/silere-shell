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

- a tunnel that is gone at one 5 s read of `/proc/net/dev` and back at the
  next has no earlier counter to compare, so `_countersRestarted` never sees
  it and the address is never marked stale. Marking it stale on any change
  to the interface list would cover it;
- the mark clears after the settle listing even when the reread did not run,
  because a read was still in flight, or failed and kept the old address.
  Marking it again on a failed read for the live uuid, and clearing it only
  while no read is running, would cover it.

The probe checks only that a rebuild sets the mark. The reread itself runs in
`_vpnProc`'s exit handler, which the probe cannot reach without test-only
aliases.
