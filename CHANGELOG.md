# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/opteon-sdc/omarchy-reolink-plugin/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/opteon-sdc/omarchy-reolink-plugin/releases/tag/v1.0.0
