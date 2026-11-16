<div align="center">

# Reolink Live for Omarchy

**Your Reolink cameras in the [Omarchy](https://omarchy.org) bar: live view, pan/tilt, presets and snapshots.
Local network only. No cloud account, no browser, no extra server.**

[![CI](https://github.com/opteon-sdc/omarchy-reolink-plugin/actions/workflows/ci.yml/badge.svg)](https://github.com/opteon-sdc/omarchy-reolink-plugin/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Omarchy shell plugin](https://img.shields.io/badge/omarchy-shell%20plugin-8a7fd4)](https://omarchy.org)

<img src="docs/preview.png" alt="The plugin panel open under the bar, showing a demo camera feed, a pan/tilt pad, presets and a list of recent events" width="560">

<sub>Shown with the bundled demo camera (<code>tests/fake-reolink-cli</code>).</sub>

</div>

## Features

- **Live view** in a panel that opens from the bar, with sub and main streams
  and an adjustable frame rate. The stream only runs while the panel is open.
- **Several cameras.** Switch between every camera registered in `reolink-cli`.
- **Camera setup in the panel.** Search your network, add a camera by IP address
  or UID, edit, disable or remove one. A new password is checked with a login
  first and handed to reolink-cli on stdin.
- **Pan and tilt.** Hold an on-screen arrow to move and let go to stop; even a quick
  click moves the camera a visible step. The arrow
  keys give short nudges, and the speed is adjustable.
- **Presets.** Jump to one with a click or a key from 1 to 9, save the current
  position under a name, or delete one.
- **Motion alerts.** Motion and AI detections (person, vehicle, animal, …) from
  every camera show up as a desktop notification with a snapshot, as a count on
  the bar icon and in an events list in the panel. Click one to watch that camera.
- **Snapshots** at full resolution, filed by day under `Pictures/Reolink/YYYY-MM-DD/`, with a
  notification.
- **Feels like part of Omarchy.** It follows your theme and fonts, uses the
  shell's own panels and keyboard handling, and is translated (English, Dutch).
- **Scriptable.** `omarchy-shell reolink toggle` works from a keybinding.

The panel only shows pan/tilt controls when the selected camera supports them.

## Requirements

| | |
|---|---|
| [Omarchy](https://omarchy.org) | with the Quickshell-based `omarchy-shell` |
| [`reolink-cli`](https://github.com/reolink/reolink-cli) | Reolink's official LAN CLI; `setup` installs it if missing |
| `ffmpeg` | `setup` installs it if missing |
| A Reolink camera, NVR or Home Hub | reachable on your local network |

## Installation

```bash
omarchy plugin add https://github.com/opteon-sdc/omarchy-reolink-plugin --enable
~/.config/omarchy/plugins/io.github.opteon-sdc.reolink/setup
```

`omarchy plugin add` only copies the plugin into place. The `setup` script
then does three things:

1. It installs `ffmpeg` with `omarchy pkg add` if it is missing.
2. It installs `reolink-cli` with Reolink's own installer if it is missing. That
   installer verifies its download against a published checksum.
3. It runs the reolink-cli gateway as the user service `reolink-gateway.service`.
   The gateway listens on `127.0.0.1:9000` only.

### Register your cameras

`reolink-cli` keeps the camera list and stores passwords encrypted. The easiest
way to register a camera is in the panel: click the camera icon in the bar
(the panel opens on camera management when none is registered), then
**Search network** or **+ Add camera**. Enter the camera's address, user and
password and click **Check and save**: the plugin logs in first and only then
saves the camera.

<img src="docs/manage.png" alt="Camera management in the panel: the registered cameras with Edit, Disable and Remove, and the Add camera form" width="520">

You can also do it in a terminal; the CLI asks for the password without echoing it:

```bash
reolink-cli discover        # find cameras on your LAN
reolink-cli device add living-room --host 192.168.1.40 --user admin
```

If `discover` finds nothing (a firewall can block its UDP replies), look up the
camera's IP address in your router or the Reolink app. For cameras behind an
NVR or Home Hub, add the hub and run `reolink-cli device expand <hub>`.

### Update and remove

```bash
omarchy plugin update io.github.opteon-sdc.reolink
omarchy plugin remove io.github.opteon-sdc.reolink
systemctl --user disable --now reolink-gateway.service   # optional
```

## Usage

Click the camera icon in the bar. To open the panel with a keyboard shortcut,
add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + C", "Cameras", "omarchy-shell reolink toggle")
```

| Input | Action |
|---|---|
| Camera buttons, `C` | Switch camera |
| `Sub` / `Main`, `M` | Switch between the light and the full-resolution stream |
| Hold an on-screen arrow | Pan/tilt until you let go (a short click moves at least 0.4 s) |
| `■` | Stop immediately |
| Arrow keys | Short pan/tilt nudge |
| Preset button, `1`–`9` | Go to a preset |
| **+ Save current position** | Save the current position as a preset |
| Camera icon, `S` | Save a full-resolution snapshot |
| Refresh icon, `R` | Reload the camera list and restart the stream |
| Cog icon | Manage cameras: add, search, edit, enable/disable, remove |
| Event in the list | Switch to that camera |
| **Clear** | Empty the events list |
| `Esc` | Close the panel |

IPC: `omarchy-shell reolink open | close | toggle`, and for events
`omarchy-shell reolink-events show CAMERA | manage | clear | unseen | list`.

### Events

Cameras report motion and AI detections to the reolink-cli gateway, which must
be running (`setup` installs it as a user service). Detection must be enabled on
the camera itself, for example with `reolink-cli --camera NAME detect`, or in
the Reolink app. Battery cameras only report events while they are awake.

## Settings

Open Omarchy's bar settings, or edit the `io.github.opteon-sdc.reolink` entry
in `~/.config/omarchy/shell.json`. For example:

```bash
omarchy bar set io.github.opteon-sdc.reolink defaultCamera living-room
```

| Key | Default | Description |
|---|---|---|
| `defaultCamera` | first camera | Camera shown when the panel opens |
| `stream` | `sub` | `sub` is lighter on CPU and network; `main` is full resolution |
| `fps` | `8` | Live frames per second (1–15) |
| `panelWidth` | `640` | Panel width in pixels (420–1400) |
| `cliPath` | `reolink-cli` on `PATH` | Path to `reolink-cli` |
| `snapshotDir` | `$(xdg-user-dir PICTURES)/Reolink` | Where snapshots are saved, in one folder per day |
| `events` | `true` | Follow motion and detection events from every camera |
| `notify` | `true` | Send a desktop notification when an event starts |
| `notifyImage` | `true` | Attach a fresh snapshot to each notification |
| `notifyCooldown` | `60` | Seconds between notifications for the same camera and event type |
| `eventTypes` | `motion,people,vehicle,dog_cat,visitor,package` | Comma-separated; also `face` and `cry` |

## How it works

```mermaid
flowchart LR
  subgraph shell["omarchy-shell (Quickshell)"]
    Panel["Panel.qml<br/>bar icon + panel"] --> Service["Service.qml<br/>cameras, PTZ, presets, registry"]
    Panel --> Manager["CameraManager.qml<br/>add, edit, remove"] --> Service
    Panel --> Live["LiveView.qml"]
    Service --> Queue["CliQueue.qml<br/>one command at a time"]
    Events["EventService.qml<br/>one per shell"] -.->|"events, unseen"| Panel
  end
  Events -->|"events stream (NDJSON)"| CLI
  Events -->|"omarchy-notification-send"| Notify["Notification"]
  Queue -->|"reolink-cli … (JSON)"| CLI["reolink-cli"]
  Live -->|"preview capture | ffmpeg"| Frames[("$XDG_RUNTIME_DIR<br/>f0…f7.jpg + latest.txt")]
  Frames --> Live
  CLI --> GW["reolink-gateway<br/>127.0.0.1:9000"] --> Cam["Reolink camera<br/>(LAN)"]
```

- **Live view.** `reolink-cli preview capture` writes the camera's raw H.264 or
  H.265 to `ffmpeg`. `ffmpeg` detects the codec and writes JPEG frames in turn
  to eight files, and records the newest one in `latest.txt`. Two `Image`
  elements take turns loading the newest frame, so the picture never flickers.
  Because every frame has its own file name, no image cache can show an old
  picture.
- **Events.** `EventService` is a shell service, so it runs once however many
  bars you have. It reads its settings from `shell.json`, runs
  `reolink-cli --all-devices events stream`, maps each event's `host:port` to the
  camera name and only counts event starts (`status` `MD`). When the stream
  stops, for example because the gateway restarts, it reconnects with a growing
  delay.
- **Commands** go through `CliQueue`, which runs one `reolink-cli` process at a
  time and parses its JSON output. Because pan/tilt commands run in order, a
  `stop` can never overtake its `move`.

## Privacy and security

- **Local only.** Everything goes through `reolink-cli` and its gateway on
  `127.0.0.1`. No traffic leaves your network, and there is no telemetry.
- **Credentials** stay in `reolink-cli`'s encrypted registry. When you add a
  camera in the panel, the password goes from the field to `reolink-cli` on
  stdin (`--password-stdin`) and the field is cleared. The plugin never stores a
  password and never puts one on a command line, in an environment variable or
  in a file.
- **Frames are temporary.** Live frames go to a private (`0700`) folder under
  `$XDG_RUNTIME_DIR`, which is RAM-backed. They are deleted when the panel
  closes, and the stream does not run while the panel is closed.
- **Notification pictures** are kept in the same private folder; only the 20
  newest are kept, and they disappear when you log out. Turn them off with
  `notifyImage`.
- **Untrusted text is plain text.** Camera and preset names come from devices,
  so every `Text` element uses `Text.PlainText`. Values are passed to processes
  as separate arguments and never placed inside shell code.

See [SECURITY.md](SECURITY.md) to report a vulnerability.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "The reolink-cli gateway is not running" | Click **Start gateway**, or run `systemctl --user status reolink-gateway` |
| No cameras listed | Open the cog menu: a camera may be disabled (the installer's examples are) |
| "Check and save" fails | The message comes from the camera: check the address, user and password, and that the gateway runs |
| Stream error "device rejected command" | Check the camera with `reolink-cli --camera NAME info`; a battery camera may be asleep |
| No events | Check `reolink-cli --camera NAME events query --last 20`; enable detection on the camera |
| High CPU use | Use the `sub` stream or a lower `fps` |
| Anything else | The shell log is in `/run/user/$UID/quickshell/by-id/*/log.log` |

## Tested hardware

See [docs/hardware.md](docs/hardware.md). Tested a camera that is not listed yet?
Please [send a hardware report](https://github.com/opteon-sdc/omarchy-reolink-plugin/issues/new?template=hardware_report.yml).

## Development

```bash
git clone https://github.com/opteon-sdc/omarchy-reolink-plugin
cd omarchy-reolink-plugin
tests/check.sh            # static checks, also run in CI
```

To try the plugin without a camera, point it at the bundled fake CLI:

```bash
omarchy bar set io.github.opteon-sdc.reolink cliPath "$PWD/tests/fake-reolink-cli"
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development loop.

## Acknowledgements

Some ideas in 1.1, such as the minimum move time for a quick PTZ click,
dated snapshot folders and the hardware report, come from
[rodrix2000/omarchy-reolink-cameras](https://github.com/rodrix2000/omarchy-reolink-cameras)
(MIT). That plugin talks to the camera's HTTP API directly; Reolink Live builds on
`reolink-cli`.

## Disclaimer

This is an independent community project. It is not affiliated with, endorsed
by or sponsored by Reolink. "Reolink" is a trademark of its owner and is used
here only to say which devices the plugin works with. It builds on the separately
licensed [`reolink-cli`](https://github.com/reolink/reolink-cli), which is not
included. Use it only with cameras you own or are authorized to administer.

## License

[MIT](LICENSE) © 2026 opteon-sdc
