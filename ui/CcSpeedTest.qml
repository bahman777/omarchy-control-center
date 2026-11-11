import QtQuick
import Quickshell.Io
import qs.Commons

// Internet speed test inside the panel: download, then upload, with live
// readouts. Uses Omarchy's own client (omarchy-network-speedtest), which
// streams one Mbps reading per line.
CcGroup {
  id: root
  title: "Internet speed"

  property string phase: ""          // "down" | "up" | ""
  property real down: -1
  property real up: -1
  property string error: ""
  readonly property bool running: proc.running

  function start() {
    down = -1; up = -1; error = ""
    run("down")
  }
  function stop() { proc.running = false; phase = "" }
  function run(which) {
    phase = which
    proc.command = ["omarchy-network-speedtest", which]
    proc.running = true
  }
  function fmt(v) { return v < 0 ? "—" : (v >= 100 ? Math.round(v) : v.toFixed(1)) + " Mbps" }

  Process {
    id: proc
    stdout: SplitParser {
      onRead: function(line) {
        var v = parseFloat(line)
        if (!isFinite(v)) return
        if (root.phase === "down") root.down = v
        else if (root.phase === "up") root.up = v
      }
    }
    stderr: SplitParser { onRead: function(line) { if (String(line).trim() !== "") root.error = String(line).trim() } }
    onExited: function(code) {
      if (root.phase === "down" && code === 0) root.run("up")
      else root.phase = ""
    }
  }

  CcRow {
    icon: String.fromCodePoint(0xF04C5)
    title: root.running ? (root.phase === "down" ? "Measuring download…" : "Measuring upload…")
      : root.down < 0 ? "Measure your connection" : "Last result"
    subtitle: root.error !== "" ? root.error
      : "↓ " + root.fmt(root.down) + "    ↑ " + root.fmt(root.up)
    subtitleColor: root.error !== "" ? Color.urgent : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
    CcButton {
      text: root.running ? "Stop" : (root.down < 0 ? "Start" : "Run again")
      onClicked: root.running ? root.stop() : root.start()
    }
  }
}
