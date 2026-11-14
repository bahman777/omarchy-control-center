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
      page.startLook = Object.assign({}, page.work)
    })
  }
  Component.onCompleted: { load(); loadBorder(); loadApps() }
  Component.onDestruction: {
    if (boosted) unboost()
    if (cc.borderPreview) cc.borderPreview = null
  }

  // ------------------------------------------------------------ tuning aids
  // What you started from, for Hold to compare.
  property var startLook: null
  property var startBorder: null
  property bool comparing: false
  function compare(on) {
    comparing = on
    if (on) {
      if (startLook) cc.hypr.previewGlass(startLook)
      if (startBorder && startBorder.style === "glass") { cc.borderPreview = startBorder; cc.hypr.previewBorder(startBorder) }
    } else {
      if (tuning || dirty) cc.hypr.previewGlass(work)
      cc.borderPreview = bdirty ? bwork : null
      if (bwork.style === "glass") cc.hypr.previewBorder(bdirty ? bwork : (cc.hypr.border || bwork))
    }
  }
  // Easy-to-see mode: windows at 55% while tuning, for this session only;
  // switched off, or on leaving the page, opacity goes back.
  property bool boosted: false
  property var boostSaved: null
  function boost() {
    boostSaved = [v("decoration:active_opacity", 1), v("decoration:inactive_opacity", 1)]
    boosted = true
    cc.runner.run(["hyprctl", "eval", "hl.config({ decoration = { active_opacity = 0.55, inactive_opacity = 0.55 } })"], null)
  }
  function unboost() {
    var s = boostSaved || [1, 1]
    boosted = false
    cc.runner.run(["hyprctl", "eval", "hl.config({ decoration = { active_opacity = " + Number(s[0]) + ", inactive_opacity = " + Number(s[1]) + " } })"], null)
  }

  // ------------------------------------------------------------ see-through apps
  property var openApps: []          // classes of open windows
  function loadApps() {
    cc.runner.run(["hyprctl", "clients", "-j"], function(code, out) {
      var seen = {}, list = []
      try { JSON.parse(out).forEach(function(c) { var k = String(c["class"] || ""); if (k && !seen[k] && /^[A-Za-z0-9._-]{1,80}$/.test(k)) { seen[k] = true; list.push(k) } }) } catch (e) {}
      page.openApps = list.sort()
    })
  }
  readonly property var appRows: {
    var saved = cc.hypr.apps || {}, all = openApps.slice()
    for (var k in saved) if (all.indexOf(k) < 0) all.push(k)
    return all.sort()
  }

  // ------------------------------------------------------------ border
  property var bwork: Glass.cleanBorder(null)
  property bool bdirty: false
  function loadBorder() {
    bwork = Glass.cleanBorder(cc.hypr.border || { style: "glass" })
    startBorder = Glass.cleanBorder(cc.hypr.border || { style: "own" })
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
    if (bdirty) cc.borderPreview = bwork.style === "glass" ? bwork : null
    if (bwork.style === "glass" && (!quiet || bdirty)) borderSoon.restart()
  }
  Timer { id: borderSoon; interval: 60; onTriggered: page.cc.hypr.previewBorder(page.bwork) }
  function saveBorder() {
    if (bwork.style === "glass") { cc.hypr.saveBorder(bwork); cc.hypr.previewBorder(bwork) }
    else { cc.hypr.saveBorder(null); cc.runner.run(["hyprctl", "reload"], null) }
    bdirty = false
    cc.borderPreview = null
    startBorder = Glass.cleanBorder(bwork)
    cc.toast(bwork.style === "glass" ? (cc.hypr.includeInstalled ? "Border saved" : "Saved for this session: press Keep after restart to keep it") : "Back to your own border")
  }
  function revertBorder() {
    bdirty = false
    cc.borderPreview = null
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
    var lk = name.indexOf("look:") === 0 ? Glass.look(name.slice(5)) : null
    work = lk ? Object.assign(Glass.defaults(), lk.values) : name === "" ? Glass.defaults() : resolve(name)
    startedFrom = lk ? "the " + lk.name + " look" : name === "" ? "Plugin defaults" : "Your “" + name + "” preset"
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
    title: "Tuning"
    subtitle: "Small changes are hard to see through an opaque window or over a smooth wallpaper. These help."
    CcSwitchRow {
      title: "Make the glass easy to see while tuning"
      subtitle: page.boosted ? "Windows are at 55% while this page is open; they go back when you switch this off or leave" : "Windows at 55% for now, so every change shows clearly"
      checked: page.boosted
      onToggled: page.boosted ? page.unboost() : page.boost()
    }
    CcRow {
      title: "Hold to compare"
      subtitle: page.comparing ? "Showing what you started from: let go to see your changes" : "Press and hold to see what you started from"
      Rectangle {
        id: cmpBtn
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: cmpText.implicitWidth + Style.space(28); height: Style.space(32)
        radius: height / 2
        color: page.comparing ? Color.accent : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, cmpMouse.containsMouse ? 0.16 : 0.08)
        border.width: 1
        border.color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.3)
        Text {
          id: cmpText
          anchors.centerIn: parent
          text: page.comparing ? "Before" : "Hold"
          color: page.comparing ? Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1) : Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }
        MouseArea {
          id: cmpMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPressed: page.compare(true)
          onReleased: page.compare(false)
          onCanceled: page.compare(false)
        }
      }
    }
    CcRow {
      icon: Icons.info
      title: "Where each change shows"
      subtitle: "Colour, tint and blur show everywhere. Edge & lens effects bend what's behind the window: drag it partly over another window to see them. Bevel and shine sit in a thin band at the edge."
    }
  }

  CcGroup {
    visible: page.available
    title: "See-through apps"
    subtitle: "For apps with no transparency of their own (Dolphin, for example), so the rest can stay at 100% with crisp text. Kitty already has its own (background_opacity)."
    header: [ CcButton { text: "Refresh"; onClicked: page.loadApps() } ]
    Repeater {
      model: page.appRows
      delegate: CcSliderRow {
        required property var modelData
        readonly property var saved: (page.cc.hypr.apps || {})[modelData]
        title: modelData
        subtitle: saved ? "See-through, saved" : (page.openApps.indexOf(modelData) >= 0 ? "Open now" : "")
        from: 0.3; to: 1; stepSize: 0.01
        value: saved ? saved[0] : 1
        valueText: current >= 0.995 ? "Off" : Math.round(current * 100) + "%"
        onCommitted: function(val) {
          if (val >= 0.995) page.cc.hypr.removeApp(modelData)
          else page.cc.hypr.setApp(modelData, val, Math.max(0.3, val - 0.05))
        }
      }
    }
  }

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
      subtitle: "Dome: rounded and magnifying. Clear lens: flat with a crisp rim. Or one of your presets."
      useDropdown: true
      dropdownWidth: Style.space(220)
      options: Glass.LOOKS.map(function(l) { return { value: "look:" + l.name, label: l.name } })
        .concat([{ value: "", label: "Plugin defaults" }])
        .concat((page.presetData.order || []).map(function(n) { return { value: n, label: n } }))
      value: ""
      onPicked: function(val) { page.startFrom(val) }
    }
  }

  CcGroup {
    visible: page.available || page.checked
    title: "Border"
    subtitle: "A frosted rim outside the window, next to the bevel, so the two read as one glass edge. Thickness here; the bevel's own width is Bevel width below."
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
    CcChoiceRow {
      visible: page.bwork.style === "glass"
      title: "Movement"
      subtitle: page.bwork.mode === "sparkle" ? "Sparks light up here and there, as if light caught the glass"
        : page.bwork.mode === "still" ? "A still frosted rim, no moving light" : "A light circles the window"
      options: [{ value: "travel", label: "Travelling" }, { value: "sparkle", label: "Sparkle" }, { value: "still", label: "Still" }]
      value: page.bwork.mode
      onPicked: function(val) { page.bset("mode", val) }
    }
    CcSliderRow {
      visible: page.bwork.style === "glass" && page.bwork.mode === "sparkle"
      title: "Sparks per minute"
      subtitle: "On average; they come at random"
      from: 2; to: 120; stepSize: 1; integer: true
      value: page.bwork.sparkRate
      valueText: String(Math.round(current))
      onCommitted: function(val) { page.bset("sparkRate", Math.round(val)) }
    }
    CcChoiceRow {
      visible: page.bwork.style === "glass" && page.bwork.mode !== "still"
      title: page.bwork.mode === "sparkle" ? "Spark colour" : "Glint colour from"
      subtitle: page.bwork.palette ? "Wallpaper: a bright take on the wallpaper's own colour" : "The wallpaper's colour isn't available (a video?)"
      options: [{ value: "white", label: "White" }, { value: "wallpaper", label: "Wallpaper" }]
      value: page.bwork.sparkColor
      onPicked: function(val) { page.bset("sparkColor", val) }
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
      visible: page.bwork.style === "glass" && page.bwork.mode !== "still"
      title: page.bwork.mode === "sparkle" ? "Spark brightness" : "Glint"
      subtitle: page.bwork.mode === "sparkle" ? "How bright each spark gets" : "Brightness of the travelling light"
      from: 0; to: 1; stepSize: 0.01
      value: page.bwork.glint
      valueText: Math.round(current * 100) + "%"
      onMoved: function(val) { page.bset("glint", val) }
      onCommitted: function(val) { page.bset("glint", val) }
    }
    CcChoiceRow {
      visible: page.bwork.style === "glass" && page.bwork.mode === "travel"
      title: "Glint length"
      options: [{ value: "short", label: "Spark" }, { value: "long", label: "Sheen" }]
      value: page.bwork.glintLength
      onPicked: function(val) { page.bset("glintLength", val) }
    }
    CcRow {
      visible: page.bwork.style === "glass" && page.bwork.mode !== "still" && page.bwork.sparkColor === "white"
      title: page.bwork.mode === "sparkle" ? "Spark colour (white)" : "Glint colour"
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
      visible: page.bwork.style === "glass" && page.bwork.mode === "travel"
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
      subtitle: modelData.subtitle + (modelData.where ? "\nWhere to look: " + modelData.where : "")
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
