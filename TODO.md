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
