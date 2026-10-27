# TODO

Deferred work worth revisiting. Each entry records why it waited, so it can be
picked up without redoing the analysis.

## Binding loop on the notification stack's `visualHeight` (top priority)

Break the binding loop Qt reports on `cardCol.visualHeight` in
`modules/notifications/NotificationPopups.qml`:

```text
WARN scene: QML Column at @modules/notifications/NotificationPopups.qml[345:17]:
Binding loop detected for property "visualHeight":
qs:@/qs/modules/notifications/NotificationPopups.qml:349:21
```

Recorded on 2026-10-26 as top priority. The user journal holds 1,584 of these
between 2026-10-06 and 2026-10-26 (`journalctl --user -u silere-shell.service
-g visualHeight`), and they bury every other shell message there, which matters
more once the lock screen relies on that journal for debugging.

`visualHeight` arrived with 94d36642 ("fix(notifications): preserve stack motion
through card changes", 2026-09-19). It reads the Column's `implicitHeight` and
each loaded slot's `visualY + height`, and feeds both the viewport's `height` and
`_cardScroll.contentHeight`. The cycle has not been traced yet; the likeliest
path runs from the viewport or flickable size back into the slots' heights or the
Column's layout, but that is unverified. Find the edge Qt flags before changing
anything, and keep the commit's motion fix (a moving card stays visible until it
lands).

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
- the mark clears after the settle listing even when a read was still in
  flight, so a read that started before the rebuild can settle on the old
  address. A failed read marks it again. Clearing it only while no read is
  running would cover the rest.

The probe checks only that a rebuild sets the mark. The reread itself runs in
`_vpnProc`'s exit handler, which the probe cannot reach without test-only
aliases.
