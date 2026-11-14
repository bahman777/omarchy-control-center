import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons
import "../GlassSpec.js" as Glass

// Glass (hyprglass): every setting of the plugin's window glass, applied to
// the screen as you change it. Tuning sets the plugin's global settings live
// (its presets are only read when Hyprland loads its config); Save keeps the
// look as a preset of our own in ~/.config/hypr/control-center.lua, Revert
// reloads Hyprland's config. Your own hyprglass files are only read.
CcPage {
  id: page

  property bool available: false
  property bool checked: false
  property var presetData: ({ presets: {}, order: [], "default": "" })
  property var work: Glass.defaults()
  property string startedFrom: ""
  property bool dirty: false
  property bool tuning: false

  function v(key, fallback) { var x = cc.hypr.value(key); return x === undefined ? fallback : x }

  // A preset with what it inherits filled in, on top of the plugin defaults.
  function resolve(name, depth) {
    var out = Glass.defaults()
    var p = (presetData.presets || {})[name]
    if (!p || (depth || 0) > 8) return out
    if (p.inherits) out = resolve(p.inherits, (depth || 0) + 1)
    for (var k in p) if (Glass.byKey(k)) { var c = Glass.clean(k, p[k]); if (c !== undefined) out[k] = c }
    return out
  }

  function load() {
    cc.runner.run(["hyprctl", "hyprglass", "status"], function(code, out) {
      page.checked = true
      page.available = code === 0 && /:\s*active/.test(String(out))
    })
    cc.runner.run(["python3", "-I", Qt.resolvedUrl("../tools/glass-presets.py").toString().replace(/^file:\/\//, "")], function(code, out) {
      try { page.presetData = JSON.parse(out) } catch (e) { page.presetData = { presets: {}, order: [], "default": "" } }
      if (page.dirty) return
      if (page.cc.hypr.glass) { page.work = Object.assign(Glass.defaults(), page.cc.hypr.glass); page.startedFrom = "Your saved look" }
      else {
        var d = page.presetData["default"] || (page.presetData.order || [])[0] || ""
        page.work = page.resolve(d)
        page.startedFrom = d ? "Your “" + d + "” preset" : "Plugin defaults"
      }
    })
  }
  Component.onCompleted: { load(); loadBorder() }

  // ------------------------------------------------------------ border
  property var bwork: Glass.cleanBorder(null)
  property bool bdirty: false
  function loadBorder() {
    bwork = Glass.cleanBorder(cc.hypr.border || { style: "glass" })
    cc.runner.run(["python3", "-I", Qt.resolvedUrl("../tools/wallpaper-palette.py").toString().replace(/^file:\/\//, "")], function(code, out) {
      try {
        var p = JSON.parse(out)
        if (p && p.accent) page.bset("palette", { accent: p.accent, base: p.base || p.accent, path: p.path }, true)
      } catch (e) {}
    })
  }
  function bset(key, value, quiet) {
    var b = {}
    for (var k in bwork) b[k] = bwork[k]
    b[key] = value
    bwork = Glass.cleanBorder(b)
    if (!quiet) bdirty = true
    if (bwork.style === "glass" && (!quiet || bdirty)) borderSoon.restart()
  }
  Timer { id: borderSoon; interval: 60; onTriggered: page.cc.hypr.previewBorder(page.bwork) }
  function saveBorder() {
    if (bwork.style === "glass") { cc.hypr.saveBorder(bwork); cc.hypr.previewBorder(bwork) }
    else { cc.hypr.saveBorder(null); cc.runner.run(["hyprctl", "reload"], null) }
    bdirty = false
    cc.toast(bwork.style === "glass" ? (cc.hypr.includeInstalled ? "Border saved" : "Saved for this session: press Keep after restart to keep it") : "Back to your own border")
  }
  function revertBorder() {
    bdirty = false
    cc.runner.run(["hyprctl", "reload"], function() { page.loadBorder() })
  }
  function rgbText(n) { return Glass.rgbHex(n) }

  function set(key, value) {
    var c = Glass.clean(key, value)
    if (c === undefined) return
    var w = {}
    for (var k in work) w[k] = work[k]
    w[key] = c
    work = w
    dirty = true
    previewSoon.restart()
  }
  Timer { id: previewSoon; interval: 60; onTriggered: { page.cc.hypr.previewGlass(page.work); page.tuning = true } }

  function startFrom(name) {
    work = name === "" ? Glass.defaults() : resolve(name)
    startedFrom = name === "" ? "Plugin defaults" : "Your “" + name + "” preset"
    dirty = true
    previewSoon.restart()
  }
  function save() {
    cc.hypr.saveGlass(work)
    dirty = false
    cc.toast(cc.hypr.includeInstalled ? "Glass saved" : "Saved for this session: press Keep after restart to keep it")
  }
  function revert() {
    dirty = false
    tuning = false
    cc.runner.run(["hyprctl", "reload"], function() { page.load() })
    cc.toast("Back to your saved look")
  }

  CcGroup {
    visible: page.checked && !page.available
    title: "Glass"
    CcRow {
      icon: Icons.info
      title: "hyprglass isn't running"
      subtitle: "This page tunes the hyprglass plugin (github.com/hyprnux/hyprglass). Install it with hyprpm, enable it, then come back."
    }
  }

  CcPersistBanner { hypr: page.cc.hypr }

  // ------------------------------------------------------------ seeing it
  CcGroup {
    visible: page.available
    title: "Seeing the glass"
    subtitle: "The glass, bevel included, is drawn inside each window, behind what the window shows. Borders sit outside the window, so you don't need to remove them to see the bevel. What hides it is the window's opacity: at 100% the window covers the glass. Lower it to let the glass and bevel through. The border's thickness and look are under Border below."
    CcSliderRow {
      title: "Active window opacity"
      from: 0.3; to: 1; stepSize: 0.01
      value: page.v("decoration:active_opacity", 1)
      valueText: Math.round(current * 100) + "%"
      onCommitted: function(val) { page.cc.hypr.set("decoration:active_opacity", val) }
    }
    CcSliderRow {
      title: "Other windows opacity"
      from: 0.3; to: 1; stepSize: 0.01
      value: page.v("decoration:inactive_opacity", 1)
      valueText: Math.round(current * 100) + "%"
      onCommitted: function(val) { page.cc.hypr.set("decoration:inactive_opacity", val) }
    }
    CcSliderRow {
      title: "Corner rounding"
      from: 0; to: 30; stepSize: 1; integer: true
      value: page.v("decoration:rounding", 0)
      valueText: Math.round(current) + " px"
      onCommitted: function(val) { page.cc.hypr.set("decoration:rounding", val) }
    }
  }

  // ------------------------------------------------------------ look
  CcGroup {
    visible: page.available
    title: "Window glass"
    subtitle: "Changes show on your windows as you make them. Started from: " + page.startedFrom + ". The bar and menus keep their own presets."
    header: [
      CcButton { text: "Revert"; enabled: page.tuning || page.dirty; tooltipText: "Reload Hyprland's config: back to your saved look"; onClicked: page.revert() },
      CcButton { text: "Save"; enabled: page.dirty; tooltipText: "Keep this look as the windows' glass"; onClicked: page.save() }
    ]
    CcChoiceRow {
      title: "Start from"
      subtitle: "Load a preset's values to tune from"
      useDropdown: true
      dropdownWidth: Style.space(220)
      options: [{ value: "", label: "Plugin defaults" }].concat((page.presetData.order || []).map(function(n) { return { value: n, label: n } }))
      value: ""
      onPicked: function(val) { page.startFrom(val) }
    }
  }

  CcGroup {
    visible: page.available || page.checked
    title: "Border"
    subtitle: "A frosted rim with a glint of light that travels around the window. It sits outside the window, next to the bevel, so the two read as one glass edge."
    header: [
      CcButton { text: "Revert"; enabled: page.bdirty; tooltipText: "Back to your saved border"; onClicked: page.revertBorder() },
      CcButton { text: "Save"; enabled: page.bdirty; onClicked: page.saveBorder() }
    ]
    CcChoiceRow {
      title: "Style"
      options: [{ value: "glass", label: "Glass reflection" }, { value: "own", label: "Your own" }]
      value: page.bwork.style
      onPicked: function(val) { page.bset("style", val) }
    }
    CcSliderRow {
      visible: page.bwork.style === "glass"
      title: "Thickness"
      from: 1; to: 12; stepSize: 1; integer: true
      value: page.bwork.width
      valueText: Math.round(current) + " px"
      onMoved: function(val) { page.bset("width", Math.round(val)) }
      onCommitted: function(val) { page.bset("width", Math.round(val)) }
    }
    CcSwitchRow {
      visible: page.bwork.style === "glass"
      title: "Take colour from the wallpaper"
      subtitle: page.bwork.palette ? "Follows your wallpaper: picked again whenever it changes" : "Can't read colours from this wallpaper (a video?): uses the rim colour"
      checked: page.bwork.followWallpaper
      onToggled: page.bset("followWallpaper", !checked)
      Row {
        visible: !!page.bwork.palette
        spacing: Style.space(4)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Repeater {
          model: page.bwork.palette ? [page.bwork.palette.accent, page.bwork.palette.base] : []
          Rectangle {
            required property var modelData
            width: Style.space(18); height: width; radius: width / 2
            color: "#" + modelData
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.4)
          }
        }
      }
    }
    CcSliderRow {
      visible: page.bwork.style === "glass" && page.bwork.followWallpaper && !!page.bwork.palette
      title: "Wallpaper colour"
      subtitle: "From a white, frosty rim to the wallpaper's own colours"
      from: 0; to: 1; stepSize: 0.01
      value: page.bwork.wallpaperMix
      valueText: Math.round(current * 100) + "%"
      onMoved: function(val) { page.bset("wallpaperMix", val) }
      onCommitted: function(val) { page.bset("wallpaperMix", val) }
    }
    CcRow {
      visible: page.bwork.style === "glass" && (!page.bwork.followWallpaper || !page.bwork.palette)
      title: "Rim colour"
      subtitle: "RRGGBB"
      Rectangle {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: Style.space(26); height: width; radius: Style.space(6)
        color: "#" + page.rgbText(page.bwork.rimColor)
      }
      TextField {
        width: Style.space(100)
        text: page.rgbText(page.bwork.rimColor)
        maximumLength: 6
        validator: RegularExpressionValidator { regularExpression: /[0-9A-Fa-f]{0,6}/ }
        onEditingFinished: if (/^[0-9A-Fa-f]{6}$/.test(text)) page.bset("rimColor", parseInt(text, 16))
      }
    }
    CcSliderRow {
      visible: page.bwork.style === "glass"
      title: "Rim strength"
      subtitle: "How visible the frosted rim is"
      from: 0; to: 1; stepSize: 0.01
      value: page.bwork.rimStrength
      valueText: Math.round(current * 100) + "%"
      onMoved: function(val) { page.bset("rimStrength", val) }
      onCommitted: function(val) { page.bset("rimStrength", val) }
    }
    CcSliderRow {
      visible: page.bwork.style === "glass"
      title: "Glint"
      subtitle: "Brightness of the travelling light"
      from: 0; to: 1; stepSize: 0.01
      value: page.bwork.glint
      valueText: Math.round(current * 100) + "%"
      onMoved: function(val) { page.bset("glint", val) }
      onCommitted: function(val) { page.bset("glint", val) }
    }
    CcChoiceRow {
      visible: page.bwork.style === "glass"
      title: "Glint length"
      options: [{ value: "short", label: "Spark" }, { value: "long", label: "Sheen" }]
      value: page.bwork.glintLength
      onPicked: function(val) { page.bset("glintLength", val) }
    }
    CcRow {
      visible: page.bwork.style === "glass"
      title: "Glint colour"
      subtitle: "RRGGBB"
      Rectangle {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: Style.space(26); height: width; radius: Style.space(6)
        color: "#" + page.rgbText(page.bwork.glintColor)
      }
      TextField {
        width: Style.space(100)
        text: page.rgbText(page.bwork.glintColor)
        maximumLength: 6
        validator: RegularExpressionValidator { regularExpression: /[0-9A-Fa-f]{0,6}/ }
        onEditingFinished: if (/^[0-9A-Fa-f]{6}$/.test(text)) page.bset("glintColor", parseInt(text, 16))
      }
    }
    CcSliderRow {
      visible: page.bwork.style === "glass"
      title: "One turn takes"
      from: 2; to: 30; stepSize: 1; integer: true
      value: page.bwork.seconds
      valueText: Math.round(current) + " s"
      onCommitted: function(val) { page.bset("seconds", Math.round(val)) }
    }
    CcRow {
      visible: page.bwork.style === "glass" && page.available
      icon: Icons.info
      title: "Live background colour on the inside edge"
      subtitle: "The border can only follow the wallpaper. For the colours actually behind each window, raise Bevel from behind and Edge glow from behind below."
    }
  }

  Repeater {
    model: page.available ? Glass.GROUPS : []
    delegate: CcGroup {
      id: grp
      required property var modelData
      title: modelData.title
      subtitle: modelData.subtitle
      Repeater {
        model: Glass.SETTINGS.filter(function(s) { return s.group === grp.modelData.id })
        delegate: Loader {
          id: ld
          required property var modelData
          width: parent ? parent.width : 0
          sourceComponent: modelData.type === "color" ? colorRow : modelData.type === "bool" ? boolRow : sliderRow
          property var spec: modelData
        }
      }
    }
  }

  Component {
    id: sliderRow
    CcSliderRow {
      readonly property var s: parent ? parent.spec : null
      title: s ? s.label : ""
      subtitle: s && s.help ? s.help : ""
      from: s ? s.min : 0; to: s ? s.max : 1
      stepSize: s && s.type === "int" ? 1 : (s && s.max - s.min > 10 ? 1 : 0.01)
      integer: !!s && s.type === "int"
      value: s ? Number(page.work[s.key]) : 0
      valueText: !s ? "" : (s.max - s.min > 10 ? String(Math.round(current)) + (/angle/.test(s.key) ? "°" : (/px|size|height/.test(s.key) ? " px" : "")) : current.toFixed(2))
      onMoved: function(val) { if (s) page.set(s.key, val) }
      onCommitted: function(val) { if (s) page.set(s.key, val) }
    }
  }
  Component {
    id: boolRow
    CcSwitchRow {
      readonly property var s: parent ? parent.spec : null
      title: s ? s.label : ""
      subtitle: s && s.help ? s.help : ""
      checked: !!s && page.work[s.key] === true
      onToggled: if (s) page.set(s.key, !checked)
    }
  }
  Component {
    id: colorRow
    CcRow {
      id: cr
      readonly property var s: parent ? parent.spec : null
      readonly property string hexValue: s ? Glass.hex(page.work[s.key]) : "00000000"
      title: s ? s.label : ""
      subtitle: s && s.help ? s.help : ""
      Rectangle {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: Style.space(26); height: width; radius: Style.space(6)
        color: "#" + cr.hexValue.slice(6, 8) + cr.hexValue.slice(0, 6)
        border.width: 1
        border.color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.3)
      }
      TextField {
        width: Style.space(120)
        text: cr.hexValue
        maximumLength: 8
        validator: RegularExpressionValidator { regularExpression: /[0-9A-Fa-f]{0,8}/ }
        onEditingFinished: if (/^[0-9A-Fa-f]{8}$/.test(text) && cr.s) page.set(cr.s.key, parseInt(text, 16))
      }
    }
  }
}
