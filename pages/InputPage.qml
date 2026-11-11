import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Keyboard, mouse and touchpad. Hyprland input options apply live.
CcPage {
  id: page

  readonly property var h: cc.hypr
  function v(k, d) { return h.value(k, d) }
  function set(k, val) { h.set(k, val) }

  property var mice: []
  property var keyboard: ({})
  readonly property bool hasTouchpad: mice.some(function(m) { return m.indexOf("touchpad") >= 0 })

  // omarchy-toggle-input-device records a disabled touchpad here.
  FileView {
    id: tpState
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/hypr/touchpad-disabled-name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }
  readonly property bool touchpadEnabled: !tpState.loaded || tpState.text().trim() === ""

  function refresh() {
    cc.runner.run(["hyprctl", "devices", "-j"], function(code, out) {
      try {
        var d = JSON.parse(out)
        page.mice = (d.mice || []).map(function(m) { return String(m.name) })
        var main = (d.keyboards || []).filter(function(k) { return k.main })[0] || (d.keyboards || [])[0] || {}
        page.keyboard = { name: String(main.name || ""), layout: String(main.layout || ""), keymap: String(main.active_keymap || "") }
      } catch (e) {}
    })
  }
  Component.onCompleted: refresh()
  Timer { interval: 3000; running: true; repeat: true; onTriggered: page.refresh() }

  CcPersistBanner { hypr: page.cc.hypr }

  CcGroup {
    title: "Keyboard"
    CcRow {
      icon: Icons.keyboard
      title: "Input sources"
      subtitle: (page.keyboard.keymap ? page.keyboard.keymap + " · " : "") + "layouts: " + (page.v("input:kb_layout", "") || page.keyboard.layout || "—")
      clickable: true
      chevron: true
      onClicked: page.cc.launchTerminal("omarchy-setup-keyboard")
    }
    CcRow {
      icon: Icons.translate
      title: "Input methods"
      subtitle: "Japanese, Korean and Chinese typing"
      clickable: true
      chevron: true
      onClicked: page.cc.launchTerminal("omarchy-setup-input")
    }
    CcSliderRow {
      title: "Repeat delay"
      subtitle: "How long a key is held before it repeats"
      from: 150; to: 1000; stepSize: 25; integer: true
      value: page.v("input:repeat_delay", 600)
      valueText: Math.round(current) + " ms"
      onCommitted: function(val) { page.set("input:repeat_delay", val) }
    }
    CcSliderRow {
      title: "Repeat rate"
      from: 10; to: 100; stepSize: 1; integer: true
      value: page.v("input:repeat_rate", 25)
      valueText: Math.round(current) + "/s"
      onCommitted: function(val) { page.set("input:repeat_rate", val) }
    }
  }

  CcGroup {
    title: "Mouse"
    CcSliderRow {
      icon: Icons.mouse
      title: "Pointer speed"
      from: -1; to: 1; stepSize: 0.05
      value: page.v("input:sensitivity", 0)
      valueText: (current > 0 ? "+" : "") + current.toFixed(2)
      onCommitted: function(val) { page.set("input:sensitivity", val) }
    }
    CcSwitchRow {
      title: "Natural scrolling"
      subtitle: "Content moves with the wheel, like on a phone"
      checked: page.v("input:natural_scroll", false)
      onToggled: page.set("input:natural_scroll", !checked)
    }
  }

  CcGroup {
    visible: page.hasTouchpad
    title: "Touchpad"
    CcSwitchRow {
      icon: Icons.touchpad
      title: "Touchpad"
      checked: page.touchpadEnabled
      onToggled: page.cc.runner.run(["omarchy-toggle-touchpad", checked ? "off" : "on"], function() { tpState.reload() })
    }
    CcSwitchRow {
      title: "Natural scrolling"
      checked: page.v("input:touchpad:natural_scroll", false)
      onToggled: page.set("input:touchpad:natural_scroll", !checked)
    }
    CcSwitchRow {
      title: "Tap to click"
      checked: page.v("input:touchpad:tap_to_click", true)
      onToggled: page.set("input:touchpad:tap_to_click", !checked)
    }
    CcSwitchRow {
      title: "Disable while typing"
      checked: page.v("input:touchpad:disable_while_typing", true)
      onToggled: page.set("input:touchpad:disable_while_typing", !checked)
    }
    CcRow {
      title: "Touchpad not responding?"
      subtitle: "Rebind the driver"
      clickable: true
      onClicked: page.cc.runner.run(["omarchy-restart-trackpad"], function() { page.cc.toast("Touchpad reset") })
    }
  }

  CcGroup {
    title: "Devices"
    Repeater {
      model: page.mice
      delegate: CcRow {
        required property var modelData
        icon: modelData.indexOf("touchpad") >= 0 ? Icons.touchpad : Icons.mouse
        title: modelData
      }
    }
  }
}
