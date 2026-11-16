import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property string camera: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  readonly property string cli: String(setting("cliPath", "reolink-cli"))

  // [{ name, host, description, tags }]
  property var cameras: []
  property bool loaded: false
  property bool gatewayUp: true
  property bool gatewayChecked: false
  property string lastError: ""
  property string status: ""

  // PTZ state of `camera`
  property bool ptzSupported: false
  property bool ptzZoom: false
  property int maxPresets: 0
  property var presets: []
  property bool moving: false
  property string direction_: ""
  property string movingCamera: ""
  property real moveStartedAt: 0

  readonly property int moveWatchdogMs: 8000
  readonly property int minMoveMs: 400

  readonly property var directions: ["left", "right", "up", "down", "left-up", "left-down", "right-up", "right-down"]

  function plain(s) {
    // Camera and preset names come from the device; keep them out of rich text paths.
    return String(s === undefined || s === null ? "" : s).replace(/</g, "‹").replace(/>/g, "›").slice(0, 64)
  }

  function refresh() {
    lastError = ""
    checkGateway()
    info.run(["device", "list"], function (ok, data, msg) {
      root.loaded = true
      if (!ok) { root.cameras = []; root.lastError = msg; return }
      var list = Array.isArray(data) ? data : (data && (data.devices || data.cameras)) || []
      var out = []
      for (var i = 0; i < list.length && out.length < 64; i++) {
        var d = list[i] || {}
        var name = d.camera || d.name || d.alias
        if (!name || d.disabled === true || d.enabled === false) continue
        if (!/^[\w .\-:@]{1,64}$/.test(String(name))) continue
        out.push({
          name: String(name),
          host: plain(d.host || (d.uid ? "UID " + d.uid : "")),
          description: plain(d.description || d.model || "")
        })
      }
      root.cameras = out
    })
  }

  function checkGateway() {
    info.run(["gateway", "status"], function (ok, data) {
      root.gatewayChecked = true
      root.gatewayUp = ok && data && data.listening === true
    })
  }

  function startGateway() {
    status = "gateway.starting"
    // Prefer the user service the setup script installs; fall back to a detached gateway.
    Quickshell.execDetached(["bash", "-c",
      "systemctl --user start reolink-gateway.service 2>/dev/null || setsid -f \"$1\" gateway start >/dev/null 2>&1",
      "reolink", cli])
    gatewayRetry.restart()
  }

  Timer {
    id: gatewayRetry
    interval: 1500
    onTriggered: { root.status = ""; root.refresh() }
  }

  function loadPtz() {
    ptzSupported = false
    presets = []
    maxPresets = 0
    var cam = camera
    if (cam === "") return
    info.run(["--camera", cam, "capabilities"], function (ok, data) {
      if (cam !== root.camera || !ok || !data) return
      var mode = String(data.ptzMode || "")
      var type = Number((data.item && data.item.ptzType) || data.ptzType || 0)
      root.ptzSupported = type > 0 || mode.indexOf("p") >= 0
      root.ptzZoom = mode.indexOf("z") >= 0
      if (root.ptzSupported) loadPresets()
    })
  }

  function loadPresets() {
    var cam = camera
    info.run(["--camera", cam, "ptz", "preset", "list"], function (ok, data) {
      if (cam !== root.camera || !ok || !data) return
      root.maxPresets = Number(data.maxPresetNum || 0)
      var list = []
      var src = data.presets || []
      for (var i = 0; i < src.length && i < 255; i++) {
        var id = Number(src[i].id !== undefined ? src[i].id : src[i].ID)
        if (!Number.isInteger(id)) continue
        list.push({ id: id, name: plain(src[i].name || String(id)) })
      }
      list.sort(function (a, b) { return a.id - b.id })
      root.presets = list
    })
  }

  function report(ok, msg) {
    if (!ok) lastError = msg
  }

  // Hold-to-move: starts a continuous move that runs until stop().
  function move(direction, speed) {
    if (camera === "" || directions.indexOf(direction) < 0) return
    delayedStop.stop()
    movingCamera = camera
    direction_ = direction
    moveStartedAt = Date.now()
    moving = true
    watchdog.restart()
    ptz.run(["--camera", camera, "ptz", "move", direction, "--speed", String(clampSpeed(speed))], report)
  }

  // A quick click still moves the camera visibly: the stop waits until minMoveMs has passed.
  function stop() {
    if (!moving) return
    var left = minMoveMs - (Date.now() - moveStartedAt)
    if (left > 0) {
      delayedStop.interval = left
      delayedStop.restart()
      return
    }
    stopNow()
  }

  // The stop goes to the camera that is moving, even after the panel switched cameras.
  function stopNow() {
    delayedStop.stop()
    watchdog.stop()
    if (!moving) return
    moving = false
    direction_ = ""
    ptz.run(["--camera", movingCamera, "ptz", "stop"], report)
  }

  Timer {
    id: delayedStop
    onTriggered: root.stopNow()
  }

  // A short pulse, for keyboard nudges.
  function nudge(direction, speed) {
    if (camera === "" || directions.indexOf(direction) < 0 || ptz.busy) return
    ptz.run(["--camera", camera, "ptz", "move", direction, "--speed", String(clampSpeed(speed)), "--duration-ms", "350"], report)
  }

  function clampSpeed(s) {
    return Math.max(1, Math.min(64, Math.round(Number(s) || 24)))
  }

  // A lost release (panel closed mid-drag) must not leave the camera turning.
  Timer {
    id: watchdog
    interval: root.moveWatchdogMs
    onTriggered: root.stopNow()
  }

  function gotoPreset(id) {
    ptz.run(["--camera", camera, "ptz", "preset", "goto", String(id)], report)
  }

  function deletePreset(id) {
    ptz.run(["--camera", camera, "ptz", "preset", "delete", String(id)], function (ok, data, msg) {
      report(ok, msg)
      if (ok) loadPresets()
    })
  }

  function savePreset(name) {
    var clean = String(name || "").trim().replace(/[\u0000-\u001f<>]/g, "").slice(0, 31)
    var used = {}
    for (var i = 0; i < presets.length; i++) used[presets[i].id] = true
    var id = 1
    while (used[id]) id++
    if (maxPresets > 0 && id >= maxPresets) { lastError = "presets.full"; return }
    var args = ["--camera", camera, "ptz", "preset", "set", String(id)]
    if (clean !== "") args.push(clean)
    ptz.run(args, function (ok, data, msg) {
      report(ok, msg)
      if (ok) loadPresets()
    })
  }

  // Saves to <Pictures>/Reolink/YYYY-MM-DD/Reolink-<camera>-YYYY-MM-DD_HH-MM-SS.jpg (local time).
  readonly property string snapshotScript: [
    "set -euo pipefail",
    "base=$4",
    "if [[ -z $base ]]; then",
    "  pictures=$(xdg-user-dir PICTURES 2>/dev/null || true)",
    "  [[ -n $pictures && $pictures != \"$HOME\" ]] || pictures=$HOME/Pictures",
    "  base=$pictures/Reolink",
    "fi",
    "dir=$base/$(date +%F)",
    "file=$dir/Reolink-$5-$(date +%F_%H-%M-%S).jpg",
    "mkdir -p \"$dir\"",
    "out=$(\"$1\" --output json --camera \"$2\" snapshot --stream \"$3\" --file \"$file\" 2>&1) || { printf '%s\\n' \"$out\"; exit 1; }",
    "jq -cn --arg f \"$file\" '{ok: true, data: {file: $f}}'"
  ].join("\n")

  function snapshot(stream) {
    var cam = camera
    if (cam === "") return
    info.runRaw(["bash", "-c", snapshotScript, "reolink-snapshot", cli, cam, stream === "sub" ? "sub" : "main",
      String(setting("snapshotDir", "")), cam.replace(/[^\w.-]/g, "_")],
      function (ok, data, msg) {
        if (!ok) { root.lastError = msg; return }
        var file = String(data && data.file || "")
        Quickshell.execDetached(["notify-send", "-a", "Reolink Live", "-i", file, cam, file])
      })
  }

  // The on-screen stop key: always sends stop, also after a preset move.
  function forceStop() {
    if (camera === "") return
    movingCamera = movingCamera !== "" && moving ? movingCamera : camera
    moving = true
    moveStartedAt = 0
    stopNow()
  }

  onCameraChanged: { stopNow(); loadPtz() }

  CliQueue { id: info; cli: root.cli }
  CliQueue { id: ptz; cli: root.cli }
}
