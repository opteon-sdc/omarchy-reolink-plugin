# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] - 2026-11-16

### Added

- **Motion and detection alerts.** A background service (manifest kind
  `service`) follows `reolink-cli events stream` for every registered camera,
  once per shell, also with several monitors.
- Desktop notifications when an event starts, with a fresh snapshot from the
  camera and a per-camera, per-type cooldown. Clicking one opens the panel on
  that camera.
- An unseen-events count on the bar icon. It clears when you open the panel.
- An **Events** list in the panel, newest first. Click an event to switch to
  its camera, or **Clear** to empty the list. Repeats of the same event within
  30 s are merged.
- Settings `events`, `notify`, `notifyImage`, `notifyCooldown` and `eventTypes`.
- IPC target `reolink-events` with `show CAMERA`, `clear`, `unseen` and `list`.
- The fake CLI streams demo events, and the checks cover the event contract and
  that every event type has a label and an icon.

## [1.1.0] - 2026-11-16

### Changed

- Renamed the plugin to **Reolink Live**. The plugin id and the repository stay
  the same, so `omarchy plugin update` keeps working.
- Snapshots are now saved under the XDG Pictures directory
  (`xdg-user-dir PICTURES`) in one folder per day, as
  `Reolink/YYYY-MM-DD/Reolink-<camera>-YYYY-MM-DD_HH-MM-SS.jpg`, using local time.
- A quick click on a pan/tilt arrow now moves the camera for at least 0.4 s, so
  even a short tap shows a visible step.
- A pan/tilt key stays lit for as long as the camera is moving in that
  direction, and the stop key flashes when pressed.
- Added marketplace metadata to the manifest: `homepage`, `repository`,
  `keywords` and bar-widget `aliases`.

### Fixed

- The pressed pan/tilt key now uses the theme's accent and background colors.
  Inside an inline component, `Color` did not resolve to the Omarchy palette.
- Switching cameras during a move now sends the stop to the camera that was
  moving, not to the newly selected one.
- Closing the panel stops a move at once, without waiting for the minimum move
  time.
- Snapshot errors from `reolink-cli` are now shown in the panel.

### Added

- `docs/hardware.md`, a list of tested hardware, and a hardware-report issue
  template.
- `tests/check.sh` runs `qmllint` with Omarchy's shell imports when Omarchy is
  installed. This catches type and property errors such as the color bug above.

## [1.0.0] - 2026-11-16

### Added

- Bar widget with a camera icon that opens a live-view panel.
- Live view through `reolink-cli preview capture` and `ffmpeg`. Main and sub
  streams are supported, and the frame rate can be set.
- Camera switcher for every enabled camera in the reolink-cli registry.
- Pan/tilt control: hold an on-screen arrow to move, use the arrow keys for
  short nudges, and set the speed. A watchdog stops any move after 8 seconds.
- Presets: list, go to (also with keys 1–9), save under a name, and delete.
- Full-resolution snapshots, saved to `~/Pictures/Reolink` with a desktop
  notification.
- Gateway detection with a "Start gateway" action, plus a `setup` script that
  installs dependencies and runs the gateway as a user service.
- English and Dutch translations.
- IPC target `reolink` (`open`, `close`, `toggle`).
- A fake `reolink-cli` for trying the plugin without cameras, static checks,
  and CI.

[Unreleased]: https://github.com/opteon-sdc/omarchy-reolink-plugin/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/opteon-sdc/omarchy-reolink-plugin/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/opteon-sdc/omarchy-reolink-plugin/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/opteon-sdc/omarchy-reolink-plugin/releases/tag/v1.0.0
