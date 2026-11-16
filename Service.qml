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
  // Every registry entry, disabled ones too: [{ name, host, uid, user, description, disabled }]
  property var devices: []
  // From `discover`: [{ host, uid, name, model, registered }]
  property var discovered: []
  property bool discovering: false
  property bool discoverDone: false
  property bool saving: false
  // A translation key ("manage.*") or a message from reolink-cli.
  property string manageStatus: ""
  property bool manageOk: false
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
      if (!ok) { root.cameras = []; root.devices = []; root.lastError = msg; return }
      var list = Array.isArray(data) ? data : (data && (data.devices || data.cameras)) || []
      var out = []
      var all = []
      for (var k = 0; k < list.length && all.length < 256; k++) {
        var e = list[k] || {}
        var n = e.camera || e.name || e.alias
        if (!n) continue
        all.push({
          name: plain(n),
          host: plain(e.host || ""),
          uid: plain(e.uid || ""),
          user: plain(e.user || ""),
          description: plain(e.description || ""),
          disabled: e.disabled === true || e.enabled === false,
          // Only names that the panel can select are managed here.
          usable: /^[\w .\-:@]{1,64}$/.test(String(n))
        })
      }
      root.devices = all
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

  // ------------------------------------------------------------ camera registry

  readonly property var namePattern: /^[\w .\-:@]{1,64}$/
  readonly property var hostPattern: /^[A-Za-z0-9.\-]{1,253}(:[0-9]{1,5})?$/
  // Reolink UIDs are 16 characters and start with digits, e.g. 95270000ABCDEFGH.
  readonly property var uidPattern: /^[0-9]{4}[0-9A-Za-z]{12}$/

  function isUid(address) {
    return uidPattern.test(String(address || "").trim())
  }

  function addressArgs(address) {
    var a = String(address || "").trim()
    if (isUid(a)) return ["--uid", a.toUpperCase()]
    // reolink-cli wants host:port; Reolink's native port is 9000.
    return ["--host", a.indexOf(":") < 0 ? a + ":9000" : a]
  }

  function setStatus(key, ok) {
    manageStatus = key
    manageOk = ok === true
  }

  function discover() {
    if (discovering) return
    discovering = true
    discoverDone = false
    setStatus("", false)
    info.run(["discover", "--timeout-secs", "3"], function (ok, data, msg) {
      root.discovering = false
      root.discoverDone = true
      if (!ok) { root.discovered = []; root.setStatus(msg, false); return }
      var list = (data && data.devices) || []
      var out = []
      for (var i = 0; i < list.length && out.length < 64; i++) {
        var d = list[i] || {}
        var host = String(d.host || "")
        var uid = String(d.uid || "")
        if (host === "" && uid === "") continue
        out.push({
          host: plain(host),
          uid: plain(uid),
          name: plain(d.name || fromScopes(d.scopes, "name")),
          model: plain(d.model || fromScopes(d.scopes, "hardware")),
          registered: isRegistered(host, uid)
        })
      }
      root.discovered = out
    })
  }

  // Scopes look like "reolink-lan://name/Front%20Door"; a list or one space-separated string.
  function fromScopes(scopes, key) {
    var list = Array.isArray(scopes) ? scopes : String(scopes || "").split(/\s+/)
    var prefix = "reolink-lan://" + key + "/"
    for (var i = 0; i < list.length; i++) {
      var sc = String(list[i] || "")
      if (sc.indexOf(prefix) === 0) {
        try { return decodeURIComponent(sc.slice(prefix.length)) } catch (e) { return sc.slice(prefix.length) }
      }
    }
    return ""
  }

  function isRegistered(host, uid) {
    var bare = String(host || "").replace(/:\d+$/, "")
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (uid !== "" && d.uid === uid) return true
      if (bare !== "" && d.host.replace(/:\d+$/, "") === bare) return true
    }
    return false
  }

  // form: { mode: "add" | "edit", name, address, user, password, description }
  // A new password is checked with a login before anything is written to the registry.
  function saveCamera(form) {
    if (saving) return
    var name = String(form.name || "").trim()
    var address = String(form.address || "").trim()
    var user = String(form.user || "").trim() || "admin"
    var password = String(form.password || "")
    var description = String(form.description || "").trim().replace(/[\u0000-\u001f]/g, "").slice(0, 120)
    var adding = form.mode !== "edit"

    if (!namePattern.test(name)) { setStatus("manage.badName", false); return }
    if (!(hostPattern.test(address) || isUid(address))) { setStatus("manage.badAddress", false); return }
    if (!/^[\w.@\-]{1,64}$/.test(user)) { setStatus("manage.badUser", false); return }
    if (adding && password === "") { setStatus("manage.needPassword", false); return }
    if (adding) {
      for (var i = 0; i < devices.length; i++)
        if (devices[i].name === name) { setStatus("manage.nameTaken", false); return }
    }

    saving = true
    setStatus("manage.checking", true)

    var target = addressArgs(address)
    var write = function () {
      root.setStatus("manage.saving", true)
      var args = (adding ? ["device", "add", name] : ["device", "update", name])
        .concat(target).concat(["--user", user])
      if (description !== "" || !adding) args = args.concat(["--description", description])
      if (password !== "") args.push("--password-stdin")
      var finish = function (ok, data, msg) {
        password = ""
        root.saving = false
        if (!ok) { root.setStatus(msg, false); return }
        root.setStatus(adding ? "manage.added" : "manage.updated", true)
        root.refresh()
        root.registryChanged()
      }
      if (password !== "") secretQueue.run(args, password, finish)
      else info.run(args, finish)
    }

    if (password === "") { write(); return }
    secretQueue.run(target.concat(["--user", user, "--password-stdin", "login"]), password, function (ok, data, msg) {
      if (!ok) { password = ""; root.saving = false; root.setStatus(msg, false); return }
      write()
    })
  }

  function removeCamera(name) {
    info.run(["device", "remove", String(name)], function (ok, data, msg) {
      root.setStatus(ok ? "manage.removed" : msg, ok)
      if (ok) { root.refresh(); root.registryChanged() }
    })
  }

  function setDisabled(name, disabled) {
    info.run(["device", "update", String(name), "--disabled", disabled ? "true" : "false"], function (ok, data, msg) {
      root.setStatus(ok ? "" : msg, ok)
      if (ok) { root.refresh(); root.registryChanged() }
    })
  }

  signal registryChanged()

  // Runs one reolink-cli command that reads a password on stdin; the password never
  // reaches a command line, an environment variable or a file.
  QtObject {
    id: secretQueue
    property var queue: []
    function run(args, password, done) {
      var q = queue.slice()
      q.push({ args: args, password: password, done: done })
      queue = q
      next()
    }
    function next() {
      if (secretProc.running || queue.length === 0) return
      var q = queue.slice()
      var job = q.shift()
      queue = q
      secretProc.job = job
      secretProc.pendingSecret = job.password
      job.password = ""
      secretProc.command = ["bash", "-c", "exec \"$@\"", "reolink", root.cli, "--output", "json"].concat(job.args)
      secretProc.running = true
    }
  }

  Process {
    id: secretProc
    property var job: null
    property string pendingSecret: ""
    running: false
    stdinEnabled: true
    stdout: StdioCollector { id: secretOut; waitForEnd: true }
    stderr: StdioCollector { id: secretErr; waitForEnd: true }
    onStarted: {
      write(pendingSecret + "\n")
      pendingSecret = ""
    }
    onExited: function (exitCode) {
      pendingSecret = ""
      var job = secretProc.job
      secretProc.job = null
      var out = String(secretOut.text || "")
      var err = String(secretErr.text || "")
      var doc = info.parse(out)
      var ok = exitCode === 0 && doc !== null && doc.ok !== false
      Qt.callLater(secretQueue.next)
      if (job && job.done) {
        if (ok) job.done(true, doc.data, "")
        else job.done(false, null, info.messageFrom(out, err, exitCode))
      }
    }
  }

  CliQueue { id: info; cli: root.cli }
  CliQueue { id: ptz; cli: root.cli }
}
