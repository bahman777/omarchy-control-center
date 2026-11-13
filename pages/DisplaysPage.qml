import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Monitors from Hyprland (follows hotplug), brightness, night light and text size.
// Resolution/scale changes are tried live with a 15 s revert, like GNOME.
CcPage {
  id: page

  property var monitors: []
  property string laptop: ""
  property real brightness: -1
  property int textSize: 0
  property var nightlight: ({})

  // Pending "keep these settings?" state: monitor key -> { prev, next }.
  // Moving one display can push others, so a trial covers several.
  property var trial: ({})
  readonly property bool trialing: Object.keys(trial).length > 0
  property int countdown: 0


  function refresh() {
    cc.runner.run(["hyprctl", "monitors", "all", "-j"], function(code, out) {
      try { page.monitors = JSON.parse(out) } catch (e) {}
    })
    cc.runner.run(["omarchy-hyprland-monitor-laptop"], function(code, out) { page.laptop = String(out).trim() })
    cc.runner.run(["brightnessctl", "-m", "-c", "backlight"], function(code, out) {
      var f = String(out).trim().split(",")
      page.brightness = f.length >= 5 && Number(f[4]) > 0 ? Number(f[2]) / Number(f[4]) : -1
    })
    cc.runner.run(["omarchy-display-text-size"], function(code, out) {
      var m = /text size:\s*(\d+)/.exec(String(out))
      if (m) page.textSize = Number(m[1])
    })
    cc.runner.run(["omarchy-toggle-nightlight", "--status"], function(code, out) {
      try { page.nightlight = JSON.parse(out) } catch (e) {}
    })
  }

  Timer { id: refreshSoon; interval: 300; onTriggered: page.refresh() }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].indexOf(event.name) >= 0) refreshSoon.restart()
    }
  }
  Component.onCompleted: refresh()

  function modeOf(m) { return m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(2) }
  function modes(m) {
    var seen = {}, list = []
    ;(m.availableModes || []).forEach(function(s) {
      var v = String(s).replace(/Hz$/, "")
      if (seen[v]) return
      seen[v] = true
      var p = /^(\d+)x(\d+)@([\d.]+)$/.exec(v)
      list.push({ value: v, label: p ? p[1] + " × " + p[2] + "  ·  " + Math.round(Number(p[3])) + " Hz" : v })
    })
    if (list.length === 0) list.push({ value: modeOf(m), label: modeOf(m) })
    return list
  }
  // Externals are saved by model ("desc:…") so they keep their place on any
  // port; the built-in panel by connector.
  function keyOf(m) {
    var d = String(m.description || "").trim()
    if (m.name !== page.laptop && /^[A-Za-z0-9 ._()\/,+-]{1,120}$/.test(d)) return "desc:" + d
    return m.name
  }
  function mirrored(m) { return !!m.mirrorOf && m.mirrorOf !== "none" }
  function currentCfg(m) {
    if (m.disabled) return { disabled: true }
    var c = { mode: modeOf(m), position: m.x + "x" + m.y, scale: m.scale }
    if (mirrored(m)) c.mirror = String(m.mirrorOf)
    // Keep what the display is doing now, so changing one thing (say the
    // scale) doesn't reset rotation, sync or colour.
    if (Number(m.transform) > 0) c.transform = Number(m.transform)
    var saved = (cc.hypr.monitors || {})[keyOf(m)] || {}
    c.vrr = saved.vrr !== undefined ? saved.vrr : (m.vrr ? 1 : 0)
    if (/2101010/.test(String(m.currentFormat || ""))) c.bitdepth = 10
    if (m.colorManagementPreset) c.cm = String(m.colorManagementPreset)
    if (m.sdrBrightness) c.sdrbrightness = Number(m.sdrBrightness)
    if (m.sdrSaturation) c.sdrsaturation = Number(m.sdrSaturation)
    return c
  }

  // changes: [{ m: hyprctl monitor, next: cfg }]
  function tryMany(changes) {
    var t = Object.assign({}, trial), any = false
    changes.forEach(function(c) {
      var k = page.keyOf(c.m)
      if (!cc.hypr.setMonitor(k, c.next, false)) return
      if (!t[k]) t[k] = { prev: page.currentCfg(c.m), next: null }
      t[k].next = c.next
      any = true
    })
    if (!any) return
    trial = t; countdown = 15
    refreshSoon.restart()
  }
  function tryMonitor(m, change) {
    var prev = currentCfg(m)
    var next = Object.assign({}, prev, change)
    tryMany([{ m: m, next: next }])
  }
  function keep() {
    for (var k in trial) cc.hypr.setMonitor(k, trial[k].next, true)
    trial = ({}); countdown = 0
    cc.toast("Display settings saved")
  }
  function revert() {
    for (var k in trial) cc.hypr.setMonitor(k, trial[k].prev, false)
    trial = ({}); countdown = 0
    refreshSoon.restart()
  }

  // ------------------------------------------------------------ arrangement
  // Displays that take part in the layout (not off, not mirroring), in logical
  // pixels, numbered left to right then top to bottom (same as Identify).
  readonly property var placed: {
    var list = monitors.filter(function(m) { return !m.disabled && !page.mirrored(m) }).map(function(m) {
      var rot = (Number(m.transform) || 0) % 2 === 1
      var w = Math.round(m.width / (m.scale || 1)), h = Math.round(m.height / (m.scale || 1))
      return { name: m.name, m: m, x: m.x, y: m.y, w: rot ? h : w, h: rot ? w : h,
               label: m.name === page.laptop ? "Built-in" : (String(m.model || "") || m.name) }
    })
    list.sort(function(a, b) { return a.x - b.x || a.y - b.y })
    list.forEach(function(p, i) { p.num = i + 1 })
    return list
  }
  readonly property string mainName: {
    for (var i = 0; i < placed.length; i++) if (placed[i].name === page.laptop) return page.laptop
    return placed.length ? placed[0].name : ""
  }
  property string selected: ""
  property string anchorName: ""
  property string align: "center"
  property string lastDir: ""
  onSelectedChanged: lastDir = ""
  function reapplyAlign() { if (lastDir) place(lastDir) }
  readonly property var selectedPlaced: placedBy(selected)
  readonly property string anchorEff: anchorName && anchorName !== selected && placedBy(anchorName) ? anchorName
    : (mainName !== selected ? mainName : (placed.filter(function(p) { return p.name !== page.selected })[0] || {}).name || "")
  function placedBy(name) { for (var i = 0; i < placed.length; i++) if (placed[i].name === name) return placed[i]; return null }
  function overlaps(a, b) { return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h }

  // Put the selected display left/right/above/below another one, push any
  // display it now covers further the same way, then shift everything so the
  // layout starts at 0,0 (negative positions upset some X11 apps).
  function place(dir) {
    var rects = placed.map(function(p) { return { name: p.name, m: p.m, x: p.x, y: p.y, w: p.w, h: p.h } })
    function find(n) { for (var i = 0; i < rects.length; i++) if (rects[i].name === n) return rects[i]; return null }
    var s = find(selected), a = find(anchorEff)
    if (!s || !a || s === a) return
    lastDir = dir
    var horiz = dir === "left" || dir === "right"
    if (dir === "right") s.x = a.x + a.w
    if (dir === "left") s.x = a.x - s.w
    if (dir === "below") s.y = a.y + a.h
    if (dir === "above") s.y = a.y - s.h
    if (horiz) s.y = align === "start" ? a.y : align === "end" ? a.y + a.h - s.h : a.y + Math.round((a.h - s.h) / 2)
    else s.x = align === "start" ? a.x : align === "end" ? a.x + a.w - s.w : a.x + Math.round((a.w - s.w) / 2)
    var moved = [s]
    for (var pass = 0; pass < rects.length * 2; pass++) {
      var bumped = false
      moved.slice().forEach(function(mv) {
        rects.forEach(function(o) {
          if (o === mv || o === s || !page.overlaps(mv, o)) return
          if (dir === "right") o.x = mv.x + mv.w
          if (dir === "left") o.x = mv.x - o.w
          if (dir === "below") o.y = mv.y + mv.h
          if (dir === "above") o.y = mv.y - o.h
          if (moved.indexOf(o) < 0) moved.push(o)
          bumped = true
        })
      })
      if (!bumped) break
    }
    var minX = Math.min.apply(null, rects.map(function(r) { return r.x }))
    var minY = Math.min.apply(null, rects.map(function(r) { return r.y }))
    var changes = []
    rects.forEach(function(r) {
      r.x -= minX; r.y -= minY
      if (r.x === r.m.x && r.y === r.m.y) return
      var next = page.currentCfg(r.m); next.position = r.x + "x" + r.y
      changes.push({ m: r.m, next: next })
    })
    tryMany(changes)
  }
  function setEnabled(m, on) {
    if (!on && placed.length <= 1 && !m.disabled) { cc.toast("That's the only display in use"); return }
    tryMany([{ m: m, next: on ? { mode: "preferred", position: "auto", scale: 1 } : { disabled: true } }])
  }
  function setMirror(m, of) {
    var next = { mode: modeOf(m), position: "auto", scale: m.scale }
    if (of) next.mirror = of
    tryMany([{ m: m, next: next }])
  }
  Timer {
    interval: 1000; repeat: true; running: page.countdown > 0
    onTriggered: { page.countdown--; if (page.countdown <= 0) page.revert() }
  }
  Component.onDestruction: if (trialing) revert()

  // ------------------------------------------------------------ confirm bar
  CcGroup {
    visible: page.trialing
    CcRow {
      icon: Icons.monitor
      iconColor: page.cc.accent
      title: "Keep these display settings?"
      subtitle: "Reverting in " + page.countdown + " s"
      CcButton { text: "Revert"; onClicked: page.revert() }
      CcButton { text: "Keep changes"; onClicked: page.keep() }
    }
  }

  CcPersistBanner { hypr: page.cc.hypr }

  CcGroup {
    title: "Arrangement"
    subtitle: page.placed.length > 1 ? "Click a display, then choose where it goes"
      : "Plug in another display and it appears here to arrange"
    header: [ CcButton { text: "Identify"; tooltipText: "Show each display's number on it"; onClicked: page.cc.identifyDisplays() } ]
    Item {
      id: canvas
      width: parent ? parent.width : 0
      height: Style.space(page.placed.length > 1 ? 210 : 150)
      readonly property real pad: Style.space(18)
      readonly property real minX: page.placed.length ? Math.min.apply(null, page.placed.map(function(p) { return p.x })) : 0
      readonly property real minY: page.placed.length ? Math.min.apply(null, page.placed.map(function(p) { return p.y })) : 0
      readonly property real spanW: page.placed.length ? Math.max.apply(null, page.placed.map(function(p) { return p.x + p.w })) - minX : 1
      readonly property real spanH: page.placed.length ? Math.max.apply(null, page.placed.map(function(p) { return p.y + p.h })) - minY : 1
      readonly property real k: Math.min((width - pad * 2) / Math.max(1, spanW), (height - pad * 2) / Math.max(1, spanH))
      readonly property real offX: (width - spanW * k) / 2
      readonly property real offY: (height - spanH * k) / 2
      Repeater {
        model: page.placed
        delegate: Rectangle {
          id: tile
          required property var modelData
          readonly property bool isSel: page.selected === modelData.name
          x: canvas.offX + (modelData.x - canvas.minX) * canvas.k + 2
          y: canvas.offY + (modelData.y - canvas.minY) * canvas.k + 2
          width: modelData.w * canvas.k - 4
          height: modelData.h * canvas.k - 4
          radius: Style.space(6)
          color: isSel ? Qt.rgba(page.cc.accent.r, page.cc.accent.g, page.cc.accent.b, 0.28) : Qt.rgba(page.cc.fg.r, page.cc.fg.g, page.cc.fg.b, 0.10)
          border.width: isSel ? 2 : 1
          border.color: isSel ? page.cc.accent : Qt.rgba(page.cc.fg.r, page.cc.fg.g, page.cc.fg.b, 0.35)
          Behavior on x { NumberAnimation { duration: 160 } }
          Behavior on y { NumberAnimation { duration: 160 } }
          Column {
            anchors.centerIn: parent
            width: parent.width - Style.space(8)
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: String(tile.modelData.num)
              color: tile.isSel ? page.cc.accent : page.cc.fg
              font.family: Style.font.menuFamily
              font.pixelSize: Math.max(14, Math.min(tile.height * 0.32, Style.space(40)))
              font.bold: true
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: tile.modelData.label + (tile.modelData.name === page.mainName ? " · main" : "")
              color: page.cc.fg
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              visible: tile.height > Style.space(70)
              text: tile.modelData.w + " × " + tile.modelData.h
              color: Qt.rgba(page.cc.fg.r, page.cc.fg.g, page.cc.fg.b, 0.6)
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: page.placed.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (page.placed.length > 1) page.selected = tile.isSel ? "" : tile.modelData.name
          }
        }
      }
    }
    CcRow {
      visible: page.placed.length > 1 && !page.selectedPlaced
      title: "Click a display above to move it"
      subtitle: "Numbers match what Identify shows on each screen"
    }
    CcChoiceRow {
      visible: !!page.selectedPlaced && page.placed.length > 2
      title: "Place display " + (page.selectedPlaced ? page.selectedPlaced.num : "") + " next to"
      options: page.placed.filter(function(p) { return p.name !== page.selected }).map(function(p) { return { value: p.name, label: p.num + " · " + p.label } })
      value: page.anchorEff
      onPicked: function(v) { page.anchorName = v }
    }
    CcRow {
      visible: !!page.selectedPlaced
      title: "Move display " + (page.selectedPlaced ? page.selectedPlaced.num : "")
      subtitle: "Relative to display " + ((page.placedBy(page.anchorEff) || {}).num || "")
      CcButton { text: "←  Left"; onClicked: page.place("left") }
      CcButton { text: "↑  Above"; onClicked: page.place("above") }
      CcButton { text: "↓  Below"; onClicked: page.place("below") }
      CcButton { text: "→  Right"; onClicked: page.place("right") }
    }
    CcChoiceRow {
      visible: !!page.selectedPlaced
      title: "Line up edges"
      subtitle: "Where it sits along the other display's edge"
      options: [{ value: "start", label: "Top / Left" }, { value: "center", label: "Center" }, { value: "end", label: "Bottom / Right" }]
      value: page.align
      onPicked: function(v) { page.align = v; if (page.selectedPlaced) page.reapplyAlign() }
    }
  }

  // ------------------------------------------------------------ monitors
  Repeater {
    model: page.monitors
    delegate: CcGroup {
      id: mon
      required property var modelData
      readonly property bool internal: modelData.name === page.laptop
      title: (internal ? "Built-in display" : String(modelData.make || "") + " " + String(modelData.model || "")).trim() || modelData.name
      subtitle: modelData.name + " · " + modelData.width + " × " + modelData.height + " · scale " + modelData.scale
        + (modelData.disabled ? " · disabled" : "") + (modelData.focused ? " · focused" : "")

      CcChoiceRow {
        icon: Icons.monitor
        title: "Resolution & refresh rate"
        useDropdown: true
        dropdownWidth: Style.space(250)
        options: page.modes(mon.modelData)
        value: page.modeOf(mon.modelData)
        onPicked: function(v) { if (v !== page.modeOf(mon.modelData)) page.tryMonitor(mon.modelData, { mode: v }) }
      }
      CcChoiceRow {
        title: "Scale"
        useDropdown: true
        dropdownWidth: Style.space(250)
        options: [1, 1.25, 1.333333, 1.5, 1.6, 1.666667, 1.75, 2, 2.5, 3].map(function(s) {
          return { value: String(s), label: Math.round(s * 100) + "%" }
        })
        value: {
          var best = "1", diff = 99
          ;[1, 1.25, 1.333333, 1.5, 1.6, 1.666667, 1.75, 2, 2.5, 3].forEach(function(s) {
            var d = Math.abs(s - mon.modelData.scale); if (d < diff) { diff = d; best = String(s) }
          })
          return best
        }
        onPicked: function(v) { if (Math.abs(Number(v) - mon.modelData.scale) > 0.001) page.tryMonitor(mon.modelData, { scale: Number(v) }) }
      }
      CcChoiceRow {
        visible: !mon.modelData.disabled
        title: "Rotation"
        options: [{ value: "0", label: "Normal" }, { value: "1", label: "90°" }, { value: "2", label: "180°" }, { value: "3", label: "270°" }]
        value: String((Number(mon.modelData.transform) || 0) % 4)
        onPicked: function(v) { page.tryMonitor(mon.modelData, { transform: Number(v) }) }
      }
      CcChoiceRow {
        visible: !mon.modelData.disabled
        title: "Adaptive sync (VRR)"
        subtitle: "Matches the refresh rate to games and video; can flicker on some panels"
        options: [{ value: "0", label: "Off" }, { value: "1", label: "On" }, { value: "2", label: "Fullscreen" }]
        value: String(page.currentCfg(mon.modelData).vrr)
        onPicked: function(v) { page.tryMonitor(mon.modelData, { vrr: Number(v) }) }
      }
      CcChoiceRow {
        visible: !mon.modelData.disabled
        title: "Colour depth"
        subtitle: "10-bit gives smoother gradients, if the display supports it"
        options: [{ value: "8", label: "8-bit" }, { value: "10", label: "10-bit" }]
        value: /2101010/.test(String(mon.modelData.currentFormat || "")) ? "10" : "8"
        onPicked: function(v) { page.tryMonitor(mon.modelData, { bitdepth: Number(v) }) }
      }
      CcChoiceRow {
        visible: !mon.modelData.disabled
        title: "Colour mode"
        subtitle: "HDR needs a display that supports it"
        options: [{ value: "auto", label: "Auto" }, { value: "srgb", label: "sRGB" }, { value: "wide", label: "Wide" }, { value: "hdr", label: "HDR" }]
        value: { var p = String(mon.modelData.colorManagementPreset || "auto"); return p === "hdredid" ? "hdr" : (["auto", "srgb", "wide", "hdr"].indexOf(p) >= 0 ? p : "auto") }
        onPicked: function(v) { page.tryMonitor(mon.modelData, { cm: v }) }
      }
      CcSliderRow {
        visible: !mon.modelData.disabled && String(mon.modelData.colorManagementPreset || "").indexOf("hdr") === 0
        title: "Brightness of normal content in HDR"
        from: 0.5; to: 2
        value: Number(mon.modelData.sdrBrightness) || 1
        onCommitted: function(v) { page.tryMonitor(mon.modelData, { sdrbrightness: v }) }
      }
      CcSliderRow {
        visible: mon.internal && page.brightness >= 0
        icon: Icons.brightness
        title: "Brightness"
        from: 0.01; to: 1; stepSize: 0.01
        value: page.brightness
        valueText: Math.round(value * 100) + "%"
        onCommitted: function(v) {
          page.brightness = v
          page.cc.runner.run(["omarchy-brightness-display", "--no-osd", "--monitor", mon.modelData.name, Math.round(v * 100) + "%"], null)
        }
      }
      CcSwitchRow {
        visible: !mon.internal
        title: "Use this display"
        subtitle: mon.modelData.disabled ? "Off: connected but not showing anything" : "On"
        checked: !mon.modelData.disabled
        onToggled: page.setEnabled(mon.modelData, !!mon.modelData.disabled)
      }
      CcChoiceRow {
        visible: !mon.internal && !mon.modelData.disabled && page.monitors.length > 1
        title: "Show"
        useDropdown: true
        dropdownWidth: Style.space(250)
        options: [{ value: "", label: "Its own desktop (extend)" }].concat(page.monitors.filter(function(o) {
          return o.name !== mon.modelData.name && !o.disabled && !page.mirrored(o)
        }).map(function(o) { return { value: o.name, label: "Same as " + (o.name === page.laptop ? "built-in display" : (String(o.model || "") || o.name)) } }))
        value: page.mirrored(mon.modelData) ? String(mon.modelData.mirrorOf) : ""
        onPicked: function(v) { if (v !== (page.mirrored(mon.modelData) ? String(mon.modelData.mirrorOf) : "")) page.setMirror(mon.modelData, v) }
      }
      CcSwitchRow {
        visible: mon.internal && page.monitors.length > 1
        title: "Mirror to external display"
        subtitle: "Show the built-in display on the external monitor"
        checked: !!mon.modelData.mirrorOf && mon.modelData.mirrorOf !== "none"
        onToggled: page.cc.runner.run(["omarchy-hyprland-monitor-internal-mirror", "toggle"], function() { refreshSoon.restart() })
      }
      CcSwitchRow {
        visible: mon.internal && page.monitors.length > 1
        title: "Use built-in display"
        subtitle: "Turn the laptop panel off while an external monitor is connected"
        checked: !mon.modelData.disabled
        onToggled: page.cc.runner.run(["omarchy-hyprland-monitor-internal", "toggle"], function() { refreshSoon.restart() })
      }
    }
  }

  // ------------------------------------------------------------ comfort
  CcGroup {
    title: "Comfort"
    CcSwitchRow {
      icon: Icons.nightlight
      title: "Night light"
      subtitle: "Warmer colors to reduce eye strain" + (page.nightlight.temperature ? " · " + page.nightlight.temperature + " K" : "")
      checked: !!page.nightlight.enabled
      onToggled: {
        var n = {}; for (var k in page.nightlight) n[k] = page.nightlight[k]
        n.enabled = !n.enabled; page.nightlight = n
        if (page.cc.nightToggle) { page.cc.nightToggle(n.enabled); refreshSoon.restart() }
        else page.cc.runner.run(["omarchy-toggle-nightlight"], function() { refreshSoon.restart() })
      }
    }
    CcRow {
      icon: String.fromCodePoint(0xF0954)
      title: "Night light schedule, warmth and brightness"
      subtitle: "In the Night Light menu of Quick Settings"
      clickable: true
      chevron: true
      onClicked: page.cc.showMenu("night")
    }
    CcSliderRow {
      visible: page.textSize > 0
      icon: Icons.textSize
      title: "Text size"
      subtitle: "Scales text in the Omarchy shell, GTK apps and terminals"
      from: 10; to: 28; stepSize: 1; integer: true
      value: page.textSize
      valueText: Math.round(value) + " px"
      onCommitted: function(v) {
        page.textSize = Math.round(v)
        page.cc.runner.run(["omarchy-display-text-size", String(Math.round(v))], null)
      }
    }
  }

  CcGroup {
    title: "Arrangement"
    CcRow {
      icon: Icons.cog
      title: "Monitor configuration file"
      subtitle: "Positions and per-monitor rules live in ~/.config/hypr/monitors.lua"
      clickable: true
      external: true
      onClicked: page.cc.launch(["omarchy-launch-editor", Quickshell.env("HOME") + "/.config/hypr/monitors.lua"])
    }
  }
}
