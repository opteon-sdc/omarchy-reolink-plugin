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
  readonly property string snapshotDir: String(setting("snapshotDir",
    (Quickshell.env("XDG_PICTURES_DIR") || Quickshell.env("HOME") + "/Pictures") + "/Reolink"))

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

  readonly property int moveWatchdogMs: 8000

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
    moving = true
    watchdog.restart()
    ptz.run(["--camera", camera, "ptz", "move", direction, "--speed", String(clampSpeed(speed))], report)
  }

  function stop() {
    watchdog.stop()
    if (!moving || camera === "") return
    moving = false
    ptz.run(["--camera", camera, "ptz", "stop"], report)
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
    onTriggered: root.stop()
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

  function snapshot(stream) {
    var cam = camera
    var stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19)
    var file = snapshotDir + "/" + cam.replace(/[^\w.-]/g, "_") + "-" + stamp + ".jpg"
    info.runRaw(["bash", "-c",
      "mkdir -p \"$(dirname \"$4\")\" && exec \"$1\" --output json --camera \"$2\" snapshot --stream \"$3\" --file \"$4\"",
      "reolink", cli, cam, stream === "sub" ? "sub" : "main", file],
      function (ok, data, msg) {
        if (!ok) { root.lastError = msg; return }
        Quickshell.execDetached(["notify-send", "-a", "Reolink", "-i", file, cam, file])
      })
  }

  onCameraChanged: { stop(); loadPtz() }

  CliQueue { id: info; cli: root.cli }
  CliQueue { id: ptz; cli: root.cli }
}
