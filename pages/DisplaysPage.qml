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

  // Pending "keep these settings?" state.
  property string trialMonitor: ""
  property var trialPrevious: null
  property var trialNext: null
  property int countdown: 0

  readonly property var night: cc.firstParty("omarchy.nightlight")

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
  function currentCfg(m) { return { mode: modeOf(m), position: m.x + "x" + m.y, scale: m.scale } }

  function tryMonitor(m, change) {
    var prev = currentCfg(m)
    var next = { mode: change.mode || prev.mode, position: prev.position, scale: change.scale || prev.scale }
    if (!cc.hypr.setMonitor(m.name, next, false)) return
    trialMonitor = m.name; trialPrevious = prev; trialNext = next; countdown = 15
    refreshSoon.restart()
  }
  function keep() {
    if (trialMonitor) cc.hypr.setMonitor(trialMonitor, trialNext, true)
    trialMonitor = ""; countdown = 0
    cc.toast("Display settings saved")
  }
  function revert() {
    if (trialMonitor && trialPrevious) cc.hypr.setMonitor(trialMonitor, trialPrevious, false)
    trialMonitor = ""; countdown = 0
    refreshSoon.restart()
  }
  Timer {
    interval: 1000; repeat: true; running: page.countdown > 0
    onTriggered: { page.countdown--; if (page.countdown <= 0) page.revert() }
  }
  Component.onDestruction: if (trialMonitor) revert()

  // ------------------------------------------------------------ confirm bar
  CcGroup {
    visible: page.trialMonitor !== ""
    CcRow {
      icon: Icons.monitor
      iconColor: Color.accent
      title: "Keep these display settings?"
      subtitle: "Reverting in " + page.countdown + " s"
      CcButton { text: "Revert"; onClicked: page.revert() }
      CcButton { text: "Keep changes"; onClicked: page.keep() }
    }
  }

  CcPersistBanner { hypr: page.cc.hypr }

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
      checked: page.night ? page.night.enabled : !!page.nightlight.enabled
      onToggled: {
        if (page.night) page.night.setNightlight(!page.night.enabled)
        else page.cc.runner.run(["omarchy-toggle-nightlight"], null)
        refreshSoon.restart()
      }
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
      chevron: true
      onClicked: page.cc.runner.detach(["omarchy-launch-editor", Quickshell.env("HOME") + "/.config/hypr/monitors.lua"])
    }
  }
}
