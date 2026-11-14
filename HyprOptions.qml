import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "HyprSpec.js" as Spec
import "GlassSpec.js" as Glass

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
  // hyprglass look saved from the Glass page ({ setting: value }), or null.
  property var glass: null
  // Glass border (GlassSpec.BORDER_DEFAULTS shape), or null for the config's own.
  property var border: null
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
  readonly property bool hasChanges: Object.keys(overrides).length > 0 || Object.keys(monitors).length > 0 || !!glass || !!border
  readonly property bool sessionOnly: hasChanges && !includeInstalled

  function checkInclude() {
    runner.run(["grep", "-qs", "control-center.lua", home + "/.config/hypr/hyprland.lua"], function(code) {
      root.includeInstalled = code === 0
    })
  }

  function installInclude() {
    runner.sh('f="$HOME/.config/hypr/hyprland.lua"; [ -f "$f" ] || exit 1; grep -q "control-center.lua" "$f" && exit 0; '
      + 'cp "$f" "$f.bak.control-center" && '
      + 'printf "\n-- Added by the Control Center plugin: settings changed in its window.\npcall(dofile, os.getenv(\"HOME\") .. \"/.config/hypr/control-center.lua\")\n" >> "$f"', [], function() {
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

  // Glass: applied live as the plugin's global settings; `persist` saves it
  // as a preset in control-center.lua (null clears it).
  function previewGlass(values) {
    runner.run(["hyprctl", "eval", Glass.liveSnippet(values)], function(code, out) {
      root.lastError = String(out).indexOf("error") === 0 ? String(out).trim() : ""
    })
  }
  function saveGlass(values) {
    var clean = null
    if (values) {
      clean = {}
      Glass.SETTINGS.forEach(function(s) { var v = Glass.clean(s.key, values[s.key]); if (v !== undefined) clean[s.key] = v })
    }
    glass = clean
    persistTimer.restart()
  }

  function previewBorder(b) {
    var lua = Glass.borderLua(b)
    if (lua) runner.run(["hyprctl", "eval", lua], null)
  }
  function saveBorder(b) {
    border = b && Glass.cleanBorder(b).style === "glass" ? Glass.cleanBorder(b) : null
    persistTimer.restart()
  }

  function resetAll() {
    overrides = ({})
    monitors = ({})
    glass = null
    border = null
    stateFile.setText("{\"options\": {}, \"monitors\": {}, \"glass\": null, \"border\": null}\n")
    luaFile.setText("-- Control Center: no window settings overridden.\n")
    runner.run(["hyprctl", "reload"], function() { refreshLater.restart() })
  }

  Timer {
    id: persistTimer
    interval: 600
    onTriggered: {
      stateFile.setText(JSON.stringify({ options: root.overrides, monitors: root.monitors, glass: root.glass, border: root.border }, null, 2) + "\n")
      luaFile.setText(Spec.overridesFile(root.overrides, root.monitors)
        + (root.glass ? "\n-- Glass look (hyprglass), from the Glass page\n" + Glass.savedLua(root.glass) : "")
        + (root.border ? "\n-- Glass border, from the Glass page (rim follows the wallpaper: " + (root.border.followWallpaper ? "yes" : "no") + ")\n" + Glass.borderLua(root.border) : ""))
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
        if (o.glass && typeof o.glass === "object") {
          var g = {}
          Glass.SETTINGS.forEach(function(s) { var v = Glass.clean(s.key, o.glass[s.key]); if (v !== undefined) g[s.key] = v })
          root.glass = g
        } else root.glass = null
        root.border = o.border && typeof o.border === "object" ? Glass.cleanBorder(o.border) : null
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
