import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Hyprland window management: layout, gaps, borders, effects, focus and
// workspaces. Changes apply live and persist to ~/.config/hypr/control-center.lua.
CcPage {
  id: page

  readonly property var h: cc.hypr
  function v(k, d) { return h.value(k, d) }
  function set(k, val) { h.set(k, val) }

  property string workspaceLayout: ""
  property var workspaces: []

  function refresh() {
    cc.runner.run(["omarchy-hyprland-workspace-layout-current"], function(code, out) { page.workspaceLayout = String(out).trim() })
    cc.runner.run(["hyprctl", "workspaces", "-j"], function(code, out) {
      try {
        var list = JSON.parse(out).filter(function(w) { return w.id > 0 })
        list.sort(function(a, b) { return a.id - b.id })
        page.workspaces = list.map(function(w) {
          return { id: w.id, name: String(w.name), windows: w.windows, monitor: String(w.monitor), title: String(w.lastwindowtitle || "") }
        })
      } catch (e) {}
    })
  }
  Timer { id: refreshSoon; interval: 250; onTriggered: page.refresh() }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (["openwindow", "closewindow", "movewindow", "movewindowv2", "workspace", "workspacev2", "createworkspace", "destroyworkspace", "configreloaded"].indexOf(event.name) >= 0)
        refreshSoon.restart()
    }
  }
  Component.onCompleted: refresh()

  readonly property string activeWs: Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.id) : ""

  CcPersistBanner { hypr: page.cc.hypr }

  // ------------------------------------------------------------ layout
  CcGroup {
    title: "Tiling layout"
    subtitle: "How new windows are arranged"
    CcChoiceRow {
      icon: Icons.windows
      title: "Default layout"
      subtitle: page.v("general:layout", "") === "scrolling" ? "Windows sit side by side on an endless horizontal strip"
        : page.v("general:layout", "") === "master" ? "One large main window, the rest stacked beside it"
        : "Each new window splits the focused one in two"
      options: [{ value: "dwindle", label: "Dwindle" }, { value: "master", label: "Master" }, { value: "scrolling", label: "Scrolling" }]
      value: page.v("general:layout", "")
      onPicked: function(val) { page.set("general:layout", val) }
    }
    CcRow {
      title: "Current workspace"
      subtitle: page.workspaceLayout ? "Workspace " + page.activeWs + " uses " + page.workspaceLayout : ""
      CcButton { text: "Cycle layout"; onClicked: page.cc.runner.run(["omarchy-hyprland-workspace-layout-toggle"], function() { refreshSoon.restart() }) }
    }
    CcSliderRow {
      visible: page.v("general:layout", "") === "scrolling"
      title: "Column width"
      subtitle: "Share of the screen each column takes"
      from: 0.2; to: 1; stepSize: 0.05
      value: page.v("scrolling:column_width", 0.5)
      valueText: Math.round(current * 100) + "%"
      onCommitted: function(val) { page.set("scrolling:column_width", val) }
    }
    CcSwitchRow {
      visible: page.v("general:layout", "") === "scrolling"
      title: "Follow focus"
      subtitle: "Scroll the strip to keep the focused column in view"
      checked: page.v("scrolling:follow_focus", true)
      onToggled: page.set("scrolling:follow_focus", !checked)
    }
    CcSwitchRow {
      visible: page.v("general:layout", "") === "dwindle"
      title: "Preserve split direction"
      subtitle: "Keep a split horizontal or vertical when the window resizes"
      checked: page.v("dwindle:preserve_split", false)
      onToggled: page.set("dwindle:preserve_split", !checked)
    }
    CcChoiceRow {
      visible: page.v("general:layout", "") === "master"
      title: "New windows open as"
      options: [{ value: "master", label: "Master" }, { value: "slave", label: "Stack" }, { value: "inherit", label: "Inherit" }]
      value: page.v("master:new_status", "slave")
      onPicked: function(val) { page.set("master:new_status", val) }
    }
  }

  // ------------------------------------------------------------ gaps & borders
  CcGroup {
    title: "Gaps & borders"
    CcSliderRow {
      title: "Gaps between windows"
      from: 0; to: 40; stepSize: 1; integer: true
      value: page.v("general:gaps_in", 5)
      valueText: Math.round(current) + " px"
      onCommitted: function(val) { page.set("general:gaps_in", val) }
    }
    CcSliderRow {
      title: "Gaps to screen edges"
      from: 0; to: 80; stepSize: 1; integer: true
      value: page.v("general:gaps_out", 10)
      valueText: Math.round(current) + " px"
      onCommitted: function(val) { page.set("general:gaps_out", val) }
    }
    CcSliderRow {
      title: "Border width"
      from: 0; to: 10; stepSize: 1; integer: true
      value: page.v("general:border_size", 2)
      valueText: Math.round(current) + " px"
      onCommitted: function(val) { page.set("general:border_size", val) }
    }
    CcSliderRow {
      title: "Corner rounding"
      from: 0; to: 30; stepSize: 1; integer: true
      value: page.v("decoration:rounding", 0)
      valueText: Math.round(current) + " px"
      onCommitted: function(val) { page.set("decoration:rounding", val) }
    }
  }

  // ------------------------------------------------------------ effects
  CcGroup {
    title: "Effects"
    CcSwitchRow {
      title: "Animations"
      checked: page.v("animations:enabled", true)
      onToggled: page.set("animations:enabled", !checked)
    }
    CcSwitchRow {
      title: "Blur"
      subtitle: "Blur behind translucent windows and the bar"
      checked: page.v("decoration:blur:enabled", true)
      onToggled: page.set("decoration:blur:enabled", !checked)
    }
    CcSwitchRow {
      title: "Shadows"
      checked: page.v("decoration:shadow:enabled", true)
      onToggled: page.set("decoration:shadow:enabled", !checked)
    }
    CcSwitchRow {
      title: "Dim inactive windows"
      checked: page.v("decoration:dim_inactive", false)
      onToggled: page.set("decoration:dim_inactive", !checked)
    }
    CcSliderRow {
      visible: page.v("decoration:dim_inactive", false)
      title: "Dim strength"
      from: 0; to: 1; stepSize: 0.05
      value: page.v("decoration:dim_strength", 0.5)
      valueText: Math.round(current * 100) + "%"
      onCommitted: function(val) { page.set("decoration:dim_strength", val) }
    }
    CcSliderRow {
      title: "Focused window opacity"
      from: 0.3; to: 1; stepSize: 0.05
      value: page.v("decoration:active_opacity", 1)
      valueText: Math.round(current * 100) + "%"
      onCommitted: function(val) { page.set("decoration:active_opacity", val) }
    }
    CcSliderRow {
      title: "Other windows opacity"
      from: 0.3; to: 1; stepSize: 0.05
      value: page.v("decoration:inactive_opacity", 1)
      valueText: Math.round(current * 100) + "%"
      onCommitted: function(val) { page.set("decoration:inactive_opacity", val) }
    }
  }

  // ------------------------------------------------------------ focus
  CcGroup {
    title: "Focus"
    CcChoiceRow {
      title: "Focus follows mouse"
      subtitle: ["Only clicks change focus", "Hovering a window focuses it", "Keyboard follows clicks, hover only highlights", "Mouse and keyboard focus are separate"][page.v("input:follow_mouse", 1)] || ""
      options: [{ value: "0", label: "Off" }, { value: "1", label: "Always" }, { value: "2", label: "Loose" }, { value: "3", label: "Separate" }]
      value: String(page.v("input:follow_mouse", 1))
      onPicked: function(val) { page.set("input:follow_mouse", Number(val)) }
    }
    CcSwitchRow {
      title: "Focus apps that ask for attention"
      subtitle: "Jump to a window when it requests activation (e.g. links opened in the browser)"
      checked: page.v("misc:focus_on_activate", false)
      onToggled: page.set("misc:focus_on_activate", !checked)
    }
  }

  // ------------------------------------------------------------ workspaces
  CcGroup {
    title: "Workspaces"
    subtitle: "Live view · click to switch"
    Repeater {
      model: page.workspaces
      delegate: CcRow {
        required property var modelData
        readonly property bool active: String(modelData.id) === page.activeWs
        icon: Icons.windows
        iconColor: active ? Color.accent : Color.menu.text
        title: "Workspace " + modelData.name + (active ? "  · current" : "")
        subtitle: modelData.windows + (modelData.windows === 1 ? " window" : " windows") + " · " + modelData.monitor + (modelData.title ? " · " + modelData.title : "")
        selected: active
        clickable: true
        onClicked: page.cc.runner.run(["hyprctl", "dispatch", "workspace", String(modelData.id)], null)
      }
    }
  }

  CcGroup {
    title: "Your changes"
    subtitle: Object.keys(page.h.overrides).length === 0 && Object.keys(page.h.monitors).length === 0
      ? "Nothing changed here yet — your hypr/*.lua files are in charge."
      : Object.keys(page.h.overrides).length + " setting(s) in ~/.config/hypr/control-center.lua"
        + (page.h.includeInstalled ? ", loaded after your own config." : " — active for this session only.")
    CcRow {
      icon: Icons.refresh
      title: "Reset window settings"
      subtitle: "Remove the Control Center overrides and reload Hyprland"
      clickable: Object.keys(page.h.overrides).length > 0 || Object.keys(page.h.monitors).length > 0
      dim: !clickable
      onClicked: page.h.resetAll()
    }
    CcRow {
      icon: Icons.cog
      title: "Edit look & feel by hand"
      subtitle: "~/.config/hypr/looknfeel.lua"
      clickable: true
      chevron: true
      onClicked: page.cc.runner.detach(["omarchy-launch-editor", Quickshell.env("HOME") + "/.config/hypr/looknfeel.lua"])
    }
    CcRow {
      visible: page.h.lastError !== ""
      icon: Icons.info
      iconColor: Color.urgent
      title: "Hyprland rejected a change"
      subtitle: page.h.lastError
    }
  }
}
