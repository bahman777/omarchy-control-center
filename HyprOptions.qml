import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "HyprSpec.js" as Spec

// Live view of the Hyprland options the Control Center exposes. Reads with
// `hyprctl getoption`, writes live with `hyprctl eval`, and persists what the
// user changed to ~/.config/hypr/control-center.lua (loaded last by
// hyprland.lua, so it wins over looknfeel.lua/input.lua).
Item {
  id: root
  visible: false

  required property var runner

  property var values: ({})
  property var overrides: ({})
  property var monitors: ({})
  property bool loaded: false
  property string lastError: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string overridesPath: home + "/.config/hypr/control-center.lua"
  readonly property string statePath: home + "/.local/state/omarchy/control-center/hypr-overrides.json"

  function value(key, fallback) {
    var v = values[key]
    return v === undefined ? fallback : v
  }

  function refresh() {
    runner.sh('for o in "$@"; do hyprctl -j getoption "$o" | tr -d "\\n"; echo; done', Spec.keys(), function(code, out) {
      var next = {}
      var lines = String(out || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var r = Spec.parseReply(lines[i])
        if (r && r.value !== undefined) next[r.key] = r.value
      }
      root.values = next
      root.loaded = true
    })
  }

  function set(key, value) {
    var v = Spec.coerce(key, value)
    if (v === undefined || Spec.OPTIONS[key].readOnly) return
    var nv = {}
    for (var k in values) nv[k] = values[k]
    nv[key] = v
    values = nv
    var no = {}
    for (var j in overrides) no[j] = overrides[j]
    no[key] = v
    overrides = no
    runner.run(["hyprctl", "eval", Spec.evalSnippet(key, v)], function(code, out) {
      root.lastError = String(out).indexOf("error") === 0 ? String(out).trim() : ""
    })
    persistTimer.restart()
  }

  // hyprland.lua only loads control-center.lua after the user agrees to it
  // (installInclude). Until then changes are live for this session only.
  property bool includeInstalled: false
  readonly property bool hasChanges: Object.keys(overrides).length > 0 || Object.keys(monitors).length > 0
  readonly property bool sessionOnly: hasChanges && !includeInstalled

  function checkInclude() {
    runner.run(["grep", "-qs", "control-center.lua", home + "/.config/hypr/hyprland.lua"], function(code) {
      root.includeInstalled = code === 0
    })
  }

  // Adds the one line that loads control-center.lua at login. The Lua line
  // goes in as an argument ($2), never spliced into the shell script, so its
  // quotes survive. Afterwards Hyprland reloads; if it reports any config
  // error, hyprland.lua is put back from the backup made just before.
  readonly property string includeLine: 'pcall(dofile, os.getenv("HOME") .. "/.config/hypr/control-center.lua")'
  function installInclude() {
    runner.sh('f="$1"; line="$2"; [ -f "$f" ] || exit 1; grep -qF "control-center.lua" "$f" && exit 0; '
      + 'cp -- "$f" "$f.bak.control-center" || exit 1; '
      + 'printf "\n-- Added by the Control Center plugin: settings changed in its window.\n%s\n" "$line" >> "$f"; '
      + 'hyprctl reload >/dev/null 2>&1; sleep 1; '
      + 'if [ -n "$(hyprctl configerrors 2>/dev/null | tr -d "[:space:]")" ]; then cp -- "$f.bak.control-center" "$f"; hyprctl reload >/dev/null 2>&1; exit 3; fi',
      [home + "/.config/hypr/hyprland.lua", includeLine], function(code) {
        if (code === 3) root.lastError = "Hyprland reported a config error, so hyprland.lua was restored from the backup"
        root.checkInclude()
      })
  }

  function isOverridden(key) { return overrides[key] !== undefined }

  // Apply a monitor layout live. `persist` false is the "try it" step; the
  // Displays page persists only once the user keeps it.
  function setMonitor(name, cfg, persist) {
    var line = Spec.monitorLua(name, cfg)
    if (!line) return false
    runner.run(["hyprctl", "eval", line], null)
    if (persist) {
      var next = {}
      for (var k in monitors) next[k] = monitors[k]
      next[name] = Spec.cleanMonitor(name, cfg)
      monitors = next
      persistTimer.restart()
    }
    return true
  }

  function resetAll() {
    overrides = ({})
    monitors = ({})
    stateFile.setText("{\"options\": {}, \"monitors\": {}}\n")
    luaFile.setText("-- Control Center: no window settings overridden.\n")
    runner.run(["hyprctl", "reload"], function() { refreshLater.restart() })
  }

  Timer {
    id: persistTimer
    interval: 600
    onTriggered: {
      stateFile.setText(JSON.stringify({ options: root.overrides, monitors: root.monitors }, null, 2) + "\n")
      luaFile.setText(Spec.overridesFile(root.overrides, root.monitors))
    }
  }

  Timer { id: refreshLater; interval: 400; onTriggered: root.refresh() }

  FileView {
    id: stateFile
    path: root.statePath
    blockLoading: true
    // The quick panel and the settings window each hold an instance.
    watchChanges: true
    onFileChanged: reload()
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var o = JSON.parse(text())
        var opts = o.options || {}
        var clean = {}
        for (var k in opts) {
          var v = Spec.coerce(k, opts[k])
          if (v !== undefined) clean[k] = v
        }
        root.overrides = clean
        var mons = {}
        for (var m in (o.monitors || {})) {
          var c = Spec.cleanMonitor(m, o.monitors[m])
          if (c) mons[m] = c
        }
        root.monitors = mons
      } catch (e) { root.overrides = ({}) }
    }
  }

  FileView {
    id: luaFile
    path: root.overridesPath
    printErrors: false
    atomicWrites: true
  }

  Process {
    id: mkState
    command: ["mkdir", "-p", root.home + "/.local/state/omarchy/control-center"]
    running: true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") refreshLater.restart()
    }
  }

  Component.onCompleted: { refresh(); checkInclude() }
}
