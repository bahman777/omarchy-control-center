import QtQuick
import Quickshell
import Quickshell.Io

// Runs argv commands (never through a shell string built from data) and hands
// back (exitCode, stdout). One short-lived Process per call.
Item {
  id: root
  visible: false

  Component {
    id: procComponent
    Process {
      id: proc
      property var callback: null
      property string out: ""
      property int code: -1
      property bool outDone: false
      property bool exitDone: false

      function finish() {
        if (!outDone || !exitDone) return
        var cb = callback
        callback = null
        if (cb) {
          try { cb(code, out) } catch (e) { console.warn("control-center: callback failed:", e) }
        }
        Qt.callLater(function() { proc.destroy() })
      }

      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: { proc.out = text; proc.outDone = true; proc.finish() }
      }
      onExited: function(exitCode) { proc.code = exitCode; proc.exitDone = true; proc.finish() }
    }
  }

  function run(argv, cb) {
    var p = procComponent.createObject(root, { command: argv, callback: cb || null })
    if (!p) return
    p.running = true
  }

  // Like run(), but the command goes through `bash -c script` with the data as
  // positional arguments ($1, $2…), so values are never spliced into code.
  function sh(script, args, cb) {
    run(["bash", "-c", script, "control-center"].concat(args || []), cb)
  }

  function detach(argv) {
    Quickshell.execDetached(argv)
  }
}
