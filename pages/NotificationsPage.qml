import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

CcPage {
  id: page

  property bool crashCapture: true
  property string dnd: ""      // "on" | "off" | "" when the shell's notification service isn't answering

  function refresh() {
    cc.runner.run(["omarchy-shell", "notifications", "isDnd"], function(code, out) {
      var s = String(out).trim()
      page.dnd = code === 0 && (s === "on" || s === "off") ? s : ""
    })
    cc.runner.run(["omarchy-toggle-enabled", "crash-capture-off"], function(code) { page.crashCapture = code !== 0 })
  }
  Component.onCompleted: refresh()
  Timer { interval: 3000; running: true; repeat: true; onTriggered: page.refresh() }

  CcGroup {
    CcSwitchRow {
      icon: page.dnd === "on" ? Icons.bellOff : Icons.bell
      title: "Do Not Disturb"
      subtitle: page.dnd === "" ? "Omarchy's notification service isn't running" : "Silence notification pop-ups; they still arrive quietly"
      checked: page.dnd === "on"
      dim: page.dnd === ""
      onToggled: page.cc.runner.run(["omarchy-toggle-notification-silencing"], function() { page.refresh() })
    }
    CcRow {
      title: "Clear all notifications"
      clickable: page.dnd !== ""
      onClicked: page.cc.runner.run(["omarchy-shell", "notifications", "dismissAll"], function() { page.cc.toast("Notifications cleared") })
    }
  }

  CcGroup {
    title: "Alerts"
    CcSwitchRow {
      title: "Crash notifications"
      subtitle: "Announce crashed programs and offer a diagnosis"
      checked: page.crashCapture
      onToggled: page.cc.runner.run(["omarchy-toggle-crash-capture"], function() {
        page.cc.runner.run(["omarchy-toggle-enabled", "crash-capture-off"], function(code) { page.crashCapture = code !== 0 })
      })
    }
    CcRow {
      title: "Send a test notification"
      clickable: true
      onClicked: page.cc.runner.run(["omarchy-notification-send", "-g", Icons.bell, "Control Center", "Notifications are working"], null)
    }
  }
}
