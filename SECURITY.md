# Security

## Reporting

Report a vulnerability privately through
[GitHub Security Advisories](https://github.com/s3rven/silere-shell/security/advisories/new).
Please don't open a public issue for anything exploitable.

Expect a first reply within a week. Accepted fixes land on `custom-branch`, credited
unless you'd rather not be.

## Scope

Silere runs as the user's own session, with their permissions. It has no daemon,
no network listener, and no privileged helper. What's in scope:

- Notification content reaching the shell over D-Bus, including icon and image paths.
- Anything the shell passes to a process it spawns.
- Files the shell reads or writes under `$XDG_CONFIG_HOME` and `$XDG_STATE_HOME`.
- The installer script under `scripts/`.

Out of scope: Quickshell, the compositor, and anything requiring an attacker who
already runs code as the user.

Notification icons and images accept Quickshell's in-memory image provider, icon names
from the installed icon theme, and files inside the session's icon directories (the system
prefixes, Nix profiles and `XDG_DATA_DIRS`). Some of those are user-writable, so they are
trusted like the user's own files; code already running as the user is out of scope. Any
other filesystem path supplied by the sender is refused.
