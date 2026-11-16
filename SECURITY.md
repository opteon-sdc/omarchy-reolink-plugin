# Security policy

Reolink Live runs inside the long-lived, unsandboxed `omarchy-shell` process,
and it controls cameras on your network. Security reports are taken seriously.

## Reporting a vulnerability

Please **do not open a public issue**. Report it privately through
[GitHub Security Advisories](https://github.com/opteon-sdc/omarchy-reolink-plugin/security/advisories/new).

Include the affected version or commit, the steps to reproduce, and the impact
you expect. You should get a reply within a week.

## Scope

In scope:

- Command or markup injection through camera names, preset names or other
  device data.
- Live frames or snapshots ending up readable by other users, or kept after the
  panel closes.
- Anything that sends camera traffic or credentials off the local machine.

Out of scope, so please report these upstream:

- `reolink-cli` and its gateway: [reolink/reolink-cli](https://github.com/reolink/reolink-cli/blob/main/SECURITY.md).
- Omarchy and its shell: [basecamp/omarchy](https://github.com/basecamp/omarchy).
- Camera firmware: Reolink.

## Design notes

- The plugin never handles camera passwords; `reolink-cli` keeps them
  encrypted in its own registry.
- The gateway that `setup` installs listens on `127.0.0.1` only.
- Live frames go to a `0700` folder under `$XDG_RUNTIME_DIR` and are deleted
  when the stream stops.
