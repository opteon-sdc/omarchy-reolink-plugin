# Contributing

Thanks for helping. Bug reports, translations and pull requests are all
welcome.

## Before you start

- For anything bigger than a small fix, open an issue first so we can agree on
  the approach.
- Keep changes focused: one pull request per fix or feature.

## Development loop

1. Install the plugin from your checkout. Plugins must be real folders, not
   symlinks:

   ```bash
   rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/io.github.opteon-sdc.reolink/
   ```

2. Reload the shell. Hot reload picks up `manifest.json` and `Panel.qml`, but it
   can keep old copies of helper components such as `LiveView.qml`, so restart
   the shell after you change one:

   ```bash
   omarchy restart shell
   ```

3. Open the panel with `omarchy-shell reolink toggle`, and read the log:

   ```bash
   tail -f /run/user/$UID/quickshell/by-id/$(ls -t /run/user/$UID/quickshell/by-id | head -1)/log.log
   ```

4. You don't need a camera. Point the plugin at the fake CLI:

   ```bash
   omarchy bar set io.github.opteon-sdc.reolink cliPath "$PWD/tests/fake-reolink-cli"
   ```

5. Run the checks before you push. CI runs the same script:

   ```bash
   tests/check.sh
   ```

## Guidelines

- **Untrusted text.** Camera and preset names come from devices. Give every
  `Text` element `textFormat: Text.PlainText`; `tests/check.sh` enforces this.
- **Processes.** Pass values as separate argv entries. When you need `bash -c`,
  refer to them as `"$1"`, `"$2"` and so on, and never build shell code by string
  concatenation.
- **Motion.** Use the shell's components (`KeyboardPanel`, `Button` and the rest)
  rather than custom animations.
- **Translations.** Add every new string to `i18n/en.json` and read it with
  `root.tr("key", "English fallback")`. Other languages may lag behind, but must
  not contain keys that `en.json` lacks. New languages are welcome: copy
  `en.json` to `<code>.json`, using a code from
  `$OMARCHY_PATH/default/i18n/locales.json`.
- **Changelog.** Add a line under `[Unreleased]` in `CHANGELOG.md`.

## Releasing

1. Bump `version` in `manifest.json` and move the `[Unreleased]` notes in
   `CHANGELOG.md` to a new version section.
2. Commit, tag `vX.Y.Z`, and push the tag. Users update with
   `omarchy plugin update io.github.opteon-sdc.reolink`.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
