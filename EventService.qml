import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Background service: one per shell, whatever the number of bars. It follows
// `reolink-cli events stream` for every registered camera, keeps a short list
// of recent events and sends a desktop notification when one starts.
Item {
  id: root

  // Injected by the shell when present.
  property var shell: null
  property var manifest: null

  // This plugin's entry in shell.json. The stream starts once it has been read.
  property var settings: null

  readonly property string pluginId: "io.github.opteon-sdc.reolink"
  readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"

  function entryIn(config) {
    var layout = config && config.bar && config.bar.layout
    if (layout && typeof layout === "object") {
      for (var section in layout) {
        var list = layout[section]
        if (!Array.isArray(list)) continue
        for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === pluginId) return list[i]
      }
    }
    var plugins = config && config.plugins
    if (Array.isArray(plugins))
      for (var j = 0; j < plugins.length; j++) if (plugins[j] && plugins[j].id === pluginId) return plugins[j]
    return {}
  }

  FileView {
    path: root.configPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.settings = root.entryIn(JSON.parse(text())) } catch (e) { if (root.settings === null) root.settings = {} }
    }
    onLoadFailed: if (root.settings === null) root.settings = {}
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  readonly property bool configured: settings !== null
  readonly property string cli: String(setting("cliPath", "reolink-cli"))
  readonly property bool enabled: setting("events", true) !== false
  readonly property bool notify: setting("notify", true) !== false
  readonly property bool notifyImage: setting("notifyImage", true) !== false
  readonly property int cooldown: Math.max(0, Math.min(3600, Number(setting("notifyCooldown", 60)) || 0))
  readonly property var knownTypes: ["motion", "people", "vehicle", "dog_cat", "face", "visitor", "package", "cry"]
  readonly property string types: {
    var wanted = String(setting("eventTypes", "motion,people,vehicle,dog_cat,visitor,package")).split(/[\s,]+/)
    var out = []
    for (var i = 0; i < wanted.length; i++)
      if (knownTypes.indexOf(wanted[i]) >= 0 && out.indexOf(wanted[i]) < 0) out.push(wanted[i])
    return out.join(",")
  }

  // Newest first: [{ key, time, camera, type, count }]
  property var events: []
  property int unseen: 0
  readonly property int maxEvents: 50
  // Repeats of the same camera and type within this window update one entry.
  readonly property int mergeSeconds: 30

  property bool streaming: false
  property string streamError: ""

  // Set by `omarchy-shell reolink-events show CAMERA` (a notification click).
  property string focusCamera: ""
  property int focusSerial: 0
  // Set by `omarchy-shell reolink-events manage`.
  property int manageSerial: 0

  property var hostToCamera: ({})
  property var lastNotified: ({})
  property real lastCameraLookup: 0

  readonly property var glyphs: ({
    motion: 0xF0D91, people: 0xF0004, vehicle: 0xF010B, dog_cat: 0xF03E9,
    face: 0xF0643, visitor: 0xF009A, package: 0xF03D7, cry: 0xF057E
  })

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function label(type) { return strings.t("event." + type, type) }

  function glyph(type) { return String.fromCodePoint(glyphs[type] || glyphs.motion) }

  function markSeen() { unseen = 0 }

  function clear() {
    events = []
    unseen = 0
  }

  function show(camera) {
    focusCamera = String(camera || "")
    focusSerial++
    unseen = 0
  }

  // ------------------------------------------------------------ stream

  readonly property string streamKey: configured && enabled && types !== "" ? cli + "|" + types : ""
  onStreamKeyChanged: restartStream()

  function restartStream() {
    retry.stop()
    backoff = 5000
    if (proc.running) { restartAfterExit = true; proc.running = false; return }
    startStream()
  }

  property bool restartAfterExit: false
  property int backoff: 5000
  property real startedAt: 0

  function startStream() {
    if (streamKey === "") { streaming = false; return }
    lookupCameras()
    proc.command = ["bash", "-c", "exec \"$@\"", "reolink-events", cli,
      "--all-devices", "events", "stream", "--timeout", "0", "--types", types]
    startedAt = Date.now()
    streamError = ""
    proc.running = true
    streaming = true
  }

  Timer {
    id: retry
    onTriggered: root.startStream()
  }

  Process {
    id: proc
    running: false
    stdout: SplitParser { onRead: function (line) { root.handleLine(line) } }
    stderr: SplitParser {
      onRead: function (line) {
        var s = String(line).trim()
        if (s !== "") root.streamError = s.slice(0, 300)
      }
    }
    onExited: function (exitCode) {
      root.streaming = false
      if (root.restartAfterExit) { root.restartAfterExit = false; root.startStream(); return }
      if (root.streamKey === "") return
      // The gateway restarts or a camera drops: reconnect, slower each time it fails fast.
      if (Date.now() - root.startedAt > 60000) root.backoff = 5000
      retry.interval = root.backoff
      root.backoff = Math.min(120000, root.backoff * 2)
      retry.start()
    }
  }

  Component.onDestruction: proc.running = false

  function handleLine(line) {
    var ev
    try { ev = JSON.parse(String(line)) } catch (e) { return }
    if (!ev || typeof ev !== "object") return
    var data = ev.data || {}
    var type = String(ev.eventType || "")
    // A motion event that the camera's AI classified is reported as that class.
    var ai = String(data.aiType || "none")
    if (type === "motion" && knownTypes.indexOf(ai) > 0) type = ai
    if (knownTypes.indexOf(type) < 0) return
    // `status` MD is the start of an event; "none" is its end.
    if (data.status !== undefined && String(data.status) !== "MD") return
    var camera = cameraFor(String(ev.device || ""))
    var time = Number(ev.timestamp) > 0 ? Number(ev.timestamp) * 1000 : Date.now()
    add(camera, type, time)
  }

  function add(camera, type, time) {
    var list = events.slice()
    var top = list.length > 0 ? list[0] : null
    if (top && top.camera === camera && top.type === type && time - top.time < mergeSeconds * 1000) {
      list[0] = { key: top.key, time: time, camera: camera, type: type, count: top.count + 1 }
    } else {
      list.unshift({ key: time + ":" + camera + ":" + type, time: time, camera: camera, type: type, count: 1 })
      if (list.length > maxEvents) list.length = maxEvents
      unseen = unseen + 1
    }
    events = list
    maybeNotify(camera, type)
  }

  function maybeNotify(camera, type) {
    if (!notify) return
    var key = camera + "|" + type
    var now = Date.now()
    if (lastNotified[key] && now - lastNotified[key] < cooldown * 1000) return
    var next = Object.assign({}, lastNotified)
    next[key] = now
    lastNotified = next
    var known = isCameraName(camera)
    Quickshell.execDetached(["bash", "-c", notifyScript, "reolink-notify",
      cli, known ? camera : "", glyph(type), notifyImage && known ? "1" : "0",
      String(now), plain(camera) + ": " + label(type),
      Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat))])
  }

  // $1 cli  $2 camera (empty when unknown)  $3 glyph  $4 attach snapshot  $5 id  $6 headline  $7 body
  readonly property string notifyScript: [
    "dir=${XDG_RUNTIME_DIR:-/tmp}/reolink-viewer/events",
    "mkdir -p \"$dir\" && chmod 700 \"$dir\"",
    "image=()",
    "if [[ $4 == 1 ]]; then",
    "  file=$dir/$5.jpg",
    "  if timeout 10 \"$1\" --camera \"$2\" snapshot --stream sub --file \"$file\" >/dev/null 2>&1 && [[ -s $file ]]; then",
    "    image=(--image \"$file\")",
    "  fi",
    "  # Keep the 20 newest pictures.",
    "  ls -1t \"$dir\"/*.jpg 2>/dev/null | tail -n +21 | xargs -r -d '\\n' rm -f --",
    "fi",
    "click=(omarchy-shell reolink open)",
    "[[ -n $2 ]] && click=(omarchy-shell reolink-events show \"$2\")",
    "exec omarchy-notification-send --app-name 'Reolink Live' -g \"$3\" \"${image[@]}\" \"$6\" \"$7\" --exec \"${click[@]}\""
  ].join("\n")

  // ------------------------------------------------------------ cameras

  function plain(s) {
    return String(s === undefined || s === null ? "" : s).replace(/</g, "‹").replace(/>/g, "›").slice(0, 64)
  }

  function isCameraName(name) {
    for (var host in hostToCamera) if (hostToCamera[host] === name) return true
    return false
  }

  // Events name the device by host:port; the registry maps that to the camera name.
  function cameraFor(device) {
    if (hostToCamera[device]) return hostToCamera[device]
    var bare = device.replace(/:\d+$/, "")
    for (var host in hostToCamera)
      if (host.replace(/:\d+$/, "") === bare) return hostToCamera[host]
    if (Date.now() - lastCameraLookup > 60000) lookupCameras()
    return plain(device)
  }

  function lookupCameras() {
    lastCameraLookup = Date.now()
    info.run(["device", "list"], function (ok, data) {
      if (!ok) return
      var list = Array.isArray(data) ? data : (data && (data.devices || data.cameras)) || []
      var map = {}
      for (var i = 0; i < list.length && i < 256; i++) {
        var d = list[i] || {}
        var name = String(d.camera || d.name || "")
        if (!d.host || !/^[\w .\-:@]{1,64}$/.test(name)) continue
        map[String(d.host)] = name
      }
      root.hostToCamera = map
    })
  }

  CliQueue { id: info; cli: root.cli }

  // ------------------------------------------------------------ IPC

  ShellIpc {
    target: "reolink-events"

    // Opens the panel on CAMERA; used by a notification click.
    function show(camera: string): void {
      root.show(camera)
      Quickshell.execDetached(["omarchy-shell", "reolink", "open"])
    }

    function clear(): void { root.clear() }

    // Opens the panel on camera management.
    function manage(): void {
      root.manageSerial++
      Quickshell.execDetached(["omarchy-shell", "reolink", "open"])
    }

    // Prints the number of events not seen yet.
    function unseen(): int { return root.unseen }

    // Prints the recent events as JSON.
    function list(): string { return JSON.stringify(root.events) }
  }
}
