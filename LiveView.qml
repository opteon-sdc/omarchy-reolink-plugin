import QtQuick
import Quickshell
import Quickshell.Io

// Live view: reolink-cli pipes the camera's raw video into ffmpeg, which writes
// frames round-robin to f0..f7.jpg in a private runtime dir and names the newest
// one in latest.txt. Each frame thus has its own URL, so no pixmap cache can
// serve a stale picture; two Images take turns so the view never blanks.
Item {
  id: root

  property string cli: "reolink-cli"
  property string camera: ""
  property string stream: "sub"
  property int fps: 8
  property bool active: false

  readonly property bool running: proc.running
  readonly property bool hasFrame: frontReady
  property string error: ""

  readonly property string frameDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/reolink-viewer/"
    + camera.replace(/[^\w.-]/g, "_") + "-" + stream

  property bool _showA: true
  property bool frontReady: false
  property string _shown: ""
  property string _err: ""
  property bool _restarting: false

  // ffmpeg is exec'd so stopping the Process ends it; reolink-cli then dies on SIGPIPE.
  readonly property string script: [
    "umask 077",
    "rm -rf \"$5\" && mkdir -p \"$5\"",
    "exec ffmpeg -hide_banner -loglevel error -nostdin -probesize 256000 -analyzeduration 500000 \\",
    "  -i <(\"$1\" --camera \"$2\" --protocol auto preview capture --stream \"$3\" --file - --packets 100000000) \\",
    "  -an -vf \"fps=$4,scale='min(1280,iw)':-2,format=yuvj420p\" -q:v 6 \\",
    "  -f segment -segment_format mjpeg -segment_time 0.001 -segment_wrap 8 -reset_timestamps 1 \\",
    "  -segment_list \"$5/latest.txt\" -segment_list_size 1 -segment_list_type flat \"$5/f%d.jpg\""
  ].join("\n")

  function start() {
    if (camera === "" || !active) return
    error = ""
    frontReady = false
    _shown = ""
    _err = ""
    proc.command = ["bash", "-c", script, "reolink-live", cli, camera, stream === "main" ? "main" : "sub",
      String(Math.max(1, Math.min(15, fps))), frameDir]
    proc.running = true
  }

  function clearImages() {
    imgA.source = ""
    imgB.source = ""
    frontReady = false
    _shown = ""
  }

  function stop() {
    proc.running = false
    clearImages()
  }

  function restart() {
    if (proc.running) {
      _restarting = true
      proc.running = false
    } else {
      start()
    }
  }

  function reload() {
    clearImages()
    error = ""
    restart()
  }

  onActiveChanged: active ? start() : stop()
  onCameraChanged: if (active) reload()
  onStreamChanged: if (active) reload()

  function errorText(text) {
    var s = String(text || "")
    var m = s.match(/"message"\s*:\s*"((?:[^"\\]|\\.)*)"/)
    if (m) return m[1].replace(/\\"/g, "\"").slice(0, 300)
    var lines = s.trim().split("\n").filter(function (l) { return l.trim() !== "" })
    return lines.length ? lines[lines.length - 1].slice(0, 300) : ""
  }

  Process {
    id: proc
    running: false
    stderr: StdioCollector { id: errOut; waitForEnd: true; onStreamFinished: root._err = text }
    onExited: function (exitCode) {
      if (root._restarting) {
        // start() clears the folder itself; a detached rm here could race the new ffmpeg.
        root._restarting = false
        Qt.callLater(root.start)
        return
      }
      // Frames are personal data: remove them as soon as the stream is gone.
      Quickshell.execDetached(["rm", "-rf", String(proc.command[proc.command.length - 1] || root.frameDir)])
      if (!root.active) return
      var text = root.errorText(errOut.text || root._err)
      root.error = text !== "" ? text : "stream.ended"
    }
  }

  FileView {
    id: latest
    path: root.frameDir + "/latest.txt"
    printErrors: false
    onLoaded: root.show(String(text()).trim())
  }

  function show(name) {
    if (!/^f[0-7]\.jpg$/.test(name) || name === _shown) return
    var back = _showA ? imgB : imgA
    if (back.status === Image.Loading) return
    _shown = name
    back.source = "file://" + frameDir + "/" + name
  }

  Timer {
    interval: Math.round(1000 / Math.max(1, Math.min(15, root.fps)))
    repeat: true
    running: root.active && proc.running
    onTriggered: latest.reload()
  }

  Image {
    id: imgA
    anchors.fill: parent
    asynchronous: true
    cache: false
    smooth: true
    fillMode: Image.PreserveAspectFit
    visible: root._showA && root.frontReady
    onStatusChanged: if (status === Image.Ready && !root._showA) { root._showA = true; root.frontReady = true }
  }

  Image {
    id: imgB
    anchors.fill: parent
    asynchronous: true
    cache: false
    smooth: true
    fillMode: Image.PreserveAspectFit
    visible: !root._showA && root.frontReady
    onStatusChanged: if (status === Image.Ready && root._showA) { root._showA = false; root.frontReady = true }
  }
}
