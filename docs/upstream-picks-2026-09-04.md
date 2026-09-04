# Selective upstream integration: 2026-09-04

## Authority and scope

The maintainer explicitly requested applicable changes from six named
upstream commits before the next release. This was a one-off exception to
README.md's release-tag policy, not an upstream release merge or permission
to import more of `upstream/main`.

The local fixed point was `75e05ba40b12247eb44ea137524eac224cadfa57` on
`custom-branch`. Four commits were selectively integrated with fork-specific
resolutions; two were excluded. The picks do not import upstream ancestry.
Future release merges still need to reconcile these changes using the
[divergence ledger](upstream-divergences.md).

## Upstream to local provenance

Source repository: [s3rven/silere-shell](https://github.com/s3rven/silere-shell).
Full hashes are retained because the original local messages omitted
cherry-pick provenance trailers.

| Upstream commit | Local commit | Resolution |
| --- | --- | --- |
| `e009c8ff44a428fa0fbc9f888754a9fe6cfc243a` | Not imported | The reusable PipeWire volume abstraction collides with the fork's sound controls and audio service. Adopting it needs a separate design decision; it is not simply an already-applied patch. |
| `17df6e5173e477014cd4830c33be11d0ea4f2fc1` | `371464dace45aa215c2e552d27e7216b5bcda1e6` | Take app-owned tray icon directories, including the fork's tray popup consumer. |
| `3a28106fd8c9cea031ec32104c315bbd7efb2ee3` | `2cf5b365c705047391153b46f4be7986205baa97` | Take notification history identity guards and preserve live state during history removal. Correct reload handling as described below. |
| `4ff498cae48d02191a8b2814b60f7f573f345b3d` | `cbdbf7e668bfc0ef8e183acc02b93085bb772daa` | Take artwork candidate fallbacks into the fork's redesigned media control, not the obsolete upstream card path. |
| `555bebf5ed402312452e089cdde1087b1894d5a7` | `85cc86d7c5f71c4f1900079494faeffc637a05b2` | Rename HyprActions to WindowActions throughout the fork, preserving its media popup behavior. |
| `78b316e27beb8f1a7379d7433d8dd6e1a337b313` | Already covered | Popup anchor remeasurement was implemented by `fa6e49f1743f7c02f5e69c6205b838c84b2f8db8`, with the comment refined by `75e05ba40b12247eb44ea137524eac224cadfa57`. |

The tray pick records the local maintainer as author rather than upstream's
`s3rven`: a timed-out cherry-pick continuation was completed with a normal
commit. The four imported commit messages also retain conflict comment
blocks. This record supplies provenance without amending or rewriting
`custom-branch` history. None of the picks restores the fork-deleted
changelog, distribution machinery, or obsolete media card.

## Review corrections

The media follow-up `b34f35c41085f9c84dd2d517a9e086049f537a6d` restricts
shared artwork fallback advancement to an open host. A closed card can
remain alive during its exit and receive a late image failure; it must not
advance the artwork candidate used by another host.

Notification follow-ups `d4c281ceb3e56cc86d5ef759123c779cf6055e3e` and
`b2b0c89eccf3eb5f9d963532d34397f660619eb8` added increasingly elaborate
process tokens. They assumed history could outlive a process. That premise
was incorrect for the pinned Quickshell 0.3.1 implementation:

- `PersistentProperties` copies values between QML engines in one process;
  it does not serialize them to disk.
- Its `loaded` signal follows property restoration. `Component.onCompleted`
  is too early to read restored history.
- Notification post-reload waits for old-engine destruction, then signals
  `trackedNotificationsChanged` and synchronously re-emits retained objects.
  Defer orphan pruning from that server signal, not from `loaded`, so live
  timestamps and read state are protected by the rebuilt list.

The correction `8c221ecd555e5aec86e9e467bdd50b04fb442c3e` removes the tokens
and unused hardening of a nonexistent Quickshell state file. It retains the
current-session flag across engine reloads, restores history on `loaded`, and describes the
setting as "Keep after reload". Cross-process disk persistence remains a
separate feature decision, not an implied capability of this setting.

Implementation evidence is Quickshell revision
`1a4716cde794a59928d9d9fc15f2afc7a95de360`, specifically
`src/core/persistentprops.cpp`, `src/core/generation.cpp`,
`src/services/notifications/qml.cpp`, and
`src/services/notifications/server.cpp`.

## Verification and remaining checks

Each integration and corrective code commit passed the repository lint and
full validation gates before commit. No settings key or generated default
changed; the fork defaults, ShellSettings references, and deploying Nix
render remain at 52 each.

The notification follow-up adds real engine reloads to the checked-in logic
probe: retained history, current-session replacement coalescing, and
retention-off clearing. An isolated offscreen process on a private D-Bus
session additionally verified a real retained notification's timestamp and
read state, one live object after reload, and exactly one archive entry on
dismissal. Two fresh processes sharing a temporary state directory each
started with empty history despite retained rows at the previous exit.

These checks do not establish interactive artwork recovery, tray rendering,
or visual notification smoothness in a deployed desktop. No production
shell restart, push, tag, configuration re-lock, or activation was performed.
