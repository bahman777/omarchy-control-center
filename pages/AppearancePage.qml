import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Omarchy theme, background, font, bar and window corners.
CcPage {
  id: page

  property string theme: ""
  property var themes: []
  property string font: ""
  property var fonts: []
  property string corners: ""
  property bool applying: false

  readonly property string barPosition: cc.shell && cc.shell.barConfig && cc.shell.barConfig.position ? String(cc.shell.barConfig.position) : "top"

  function refresh() {
    cc.runner.run(["omarchy-theme-current"], function(code, out) { page.theme = String(out).trim() })
    cc.runner.run(["omarchy-font-current"], function(code, out) { page.font = String(out).trim() })
    cc.runner.run(["omarchy-hyprland-corners"], function(code, out) { page.corners = String(out).trim() })
  }
  Component.onCompleted: {
    refresh()
    cc.runner.run(["omarchy-theme-list"], function(code, out) {
      page.themes = String(out).split("\n").map(function(s) { return s.trim() }).filter(function(s) { return s !== "" }).slice(0, 2000)
    })
    cc.runner.run(["omarchy-font-list"], function(code, out) {
      page.fonts = String(out).split("\n").map(function(s) { return s.trim() }).filter(function(s) { return s !== "" }).slice(0, 500)
    })
  }

  function setTheme(name) {
    if (!name || name === theme) return
    applying = true
    cc.runner.run(["omarchy-theme-set", name], function() { page.applying = false; page.refresh() })
  }

  CcGroup {
    title: "Theme"
    CcRow {
      icon: Icons.palette
      title: "Theme"
      subtitle: page.applying ? "Applying…" : page.themes.length + " themes installed"
      SearchableDropdown {
        width: Style.space(260)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        options: page.themes
        value: page.theme
        foreground: page.cc.fg
        onChanged: function(v) { page.setTheme(v) }
      }
    }
    CcRow {
      title: "Browse themes with previews"
      clickable: true
      external: true
      onClicked: { page.cc.launch(["omarchy-theme-switcher"]) }
    }
    CcRow {
      title: "Install a theme from git"
      clickable: true
      external: true
      onClicked: page.cc.launchTerminal("omarchy-theme-install")
    }
  }

  CcGroup {
    title: "Background"
    CcRow {
      icon: Icons.image
      title: "Background"
      subtitle: "Pick from the current theme's backgrounds"
      CcButton { text: "Next"; onClicked: page.cc.runner.run(["omarchy-theme-bg-next"], null) }
      CcButton { text: "Choose…"; tooltipText: "Opens Omarchy's background picker"; onClicked: { page.cc.launch(["omarchy-theme-bg-switcher"]) } }
    }
  }

  CcGroup {
    title: "Text"
    CcRow {
      icon: Icons.formatFont
      title: "Monospace font"
      subtitle: "Used by terminals, the bar and the shell"
      SearchableDropdown {
        width: Style.space(260)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        options: page.fonts
        value: page.font
        foreground: page.cc.fg
        onChanged: function(v) {
          if (v && v !== page.font) page.cc.runner.run(["omarchy-font-set", v], function() { page.refresh() })
        }
      }
    }
  }

  CcGroup {
    title: "Bar"
    CcChoiceRow {
      title: "Position"
      options: [{ value: "top", label: "Top" }, { value: "bottom", label: "Bottom" }, { value: "left", label: "Left" }, { value: "right", label: "Right" }]
      value: page.barPosition
      onPicked: function(v) { page.cc.runner.run(["omarchy-bar", "position", v], null) }
    }
    CcChoiceRow {
      title: "Background"
      options: [{ value: "opaque", label: "Opaque" }, { value: "glassy", label: "Glassy" }, { value: "none", label: "None" }]
      value: ""
      onPicked: function(v) { page.cc.runner.run(["omarchy-bar", "background", v], null) }
    }
  }

  CcGroup {
    title: "Windows"
    CcChoiceRow {
      title: "Window corners"
      options: [{ value: "theme", label: "Theme" }, { value: "sharp", label: "Sharp" }, { value: "rounded", label: "Rounded" }]
      value: page.corners
      onPicked: function(v) { page.cc.runner.run(["omarchy-hyprland-corners", v], function() { page.refresh() }) }
    }
  }
}
