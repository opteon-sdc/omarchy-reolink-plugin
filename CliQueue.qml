import QtQuick
import Quickshell
import Quickshell.Io

// Runs reolink-cli commands one at a time, so a PTZ `stop` can never overtake its `move`.
Item {
  id: root

  property string cli: "reolink-cli"
  readonly property bool busy: proc.running || _queue.length > 0

  property var _queue: []
  property var _current: null
  property string _out: ""
  property string _err: ""

  // args: reolink-cli arguments; done(ok, data, message)
  function run(args, done) {
    // Through bash so a missing binary still ends in onExited (exit 127).
    _push({ command: ["bash", "-c", "exec \"$@\"", "reolink", cli, "--output", "json"].concat(args), done: done })
  }

  // A raw command (argv) whose stdout is a reolink-cli JSON document.
  function runRaw(command, done) {
    _push({ command: command, done: done })
  }

  function _push(job) {
    var q = _queue.slice()
    q.push(job)
    _queue = q
    _next()
  }

  function _next() {
    if (proc.running || _queue.length === 0) return
    var q = _queue.slice()
    _current = q.shift()
    _queue = q
    _out = ""
    _err = ""
    proc.command = _current.command
    proc.running = true
  }

  function parse(text) {
    var s = String(text || "")
    var start = s.indexOf("{")
    var end = s.lastIndexOf("}")
    if (start < 0 || end <= start) return null
    try { return JSON.parse(s.slice(start, end + 1)) } catch (e) { return null }
  }

  function messageFrom(out, err, code) {
    var doc = parse(out) || parse(err)
    if (doc && doc.error && doc.error.message) return String(doc.error.message)
    var text = String(err || out || "").trim()
    if (code === 127 || /No such file|not found/.test(text)) return "reolink-cli not found"
    return text !== "" ? text.split("\n")[0].slice(0, 300) : "reolink-cli exited with " + code
  }

  Process {
    id: proc
    running: false
    stdout: StdioCollector { id: outCollector; waitForEnd: true; onStreamFinished: root._out = text }
    stderr: StdioCollector { id: errCollector; waitForEnd: true; onStreamFinished: root._err = text }
    onExited: function (exitCode) {
      var out = String(outCollector.text || root._out || "")
      var err = String(errCollector.text || root._err || "")
      var job = root._current
      root._current = null
      var doc = root.parse(out)
      var ok = exitCode === 0 && doc !== null && doc.ok !== false
      Qt.callLater(root._next)
      if (job && job.done) {
        if (ok) job.done(true, doc.data, "")
        else job.done(false, null, root.messageFrom(out, err, exitCode))
      }
    }
  }
}
