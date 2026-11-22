import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../ui"
import "../quick"
import "../Icons.js" as Icons

// Notification center and who handles notifications.
CcPage {
  id: page

  readonly property var svc: cc.notifService
  readonly property bool active: !!svc && svc.active
  property bool crashCapture: true
  property string otherDnd: ""   // DND of Omarchy's/Island's service when ours is off

  function refresh() {
    if (!active) cc.runner.run(["omarchy-shell", "notifications", "isDnd"], function(code, out) {
      var s = String(out).trim()
      page.otherDnd = code === 0 && (s === "on" || s === "off") ? s : ""
    })
    cc.runner.run(["omarchy-toggle-enabled", "crash-capture-off"], function(code) { page.crashCapture = code !== 0 })
  }
  Component.onCompleted: refresh()
  Timer { interval: 3000; running: true; repeat: true; onTriggered: page.refresh() }

  CcGroup {
    title: "Notification center"
    CcSwitchRow {
      icon: Icons.bell
      title: "Use Quick Settings for notifications"
      subtitle: !page.svc ? "Starting…"
        : page.svc.owner === "control-center" ? "On: pop-ups with actions and replies, and the full list here"
        : page.svc.owner === "starting" ? "Taking over from " + (page.svc.islandOwns ? "Dynamic Island" : "Omarchy") + "…"
        : page.svc.owner === "island" ? "Off: Dynamic Island handles notifications"
        : "Off: Omarchy handles notifications"
      checked: !!page.svc && page.svc.wants
      busy: !page.svc
      tip: "Only one program can show notifications. Turning this on asks Dynamic Island (or Omarchy) to hand them over; turning it off gives them back."
      onToggled: if (page.svc) page.svc.setEnabled(!page.svc.wants)
    }
    CcSwitchRow {
      icon: (page.active ? page.svc.dnd : page.otherDnd === "on") ? Icons.bellOff : Icons.bell
      title: "Do Not Disturb"
      subtitle: "Hide pop-ups; notifications still collect here. Critical ones still show."
      checked: page.active ? page.svc.dnd : page.otherDnd === "on"
      dim: !page.active && page.otherDnd === ""
      onToggled: {
        if (page.active) page.svc.setDnd(!page.svc.dnd)
        else page.cc.runner.run(["omarchy-toggle-notification-silencing"], function() { page.refresh() })
      }
    }
    CcSwitchRow {
      visible: page.active
      icon: page.active && page.svc.sounds ? Icons.volume : Icons.volumeOff
      title: "Notification sounds"
      subtitle: "Play the sound an app asks for. Silent during Do Not Disturb, except critical ones."
      checked: page.active && page.svc.sounds
      onToggled: if (page.active) page.svc.setSounds(!page.svc.sounds)
    }
  }

  CcGroup {
    visible: page.active
    title: page.active && page.svc.count ? page.svc.count + (page.svc.count === 1 ? " notification" : " notifications") : "No notifications"
    header: [
      CcButton { visible: page.active && page.svc.count > 0; text: "Clear all"; onClicked: page.svc.clearAll() }
    ]
  }
  property var keys: []
  function syncKeys() { keys = (page.active && page.svc) ? page.svc.keysOf(page.svc.rows, keys) : [] }
  onActiveChanged: syncKeys()
  Connections { target: page.svc; ignoreUnknownSignals: true; function onRowsChanged() { page.syncKeys() } }
  Timer { interval: 0; running: true; onTriggered: page.syncKeys() }

  Column {
    visible: page.active
    width: parent ? parent.width : 0
    spacing: Style.space(8)
    Repeater {
      // Ids, not the rows (see QuickContent): keeps a reply being typed.
      model: page.keys
      delegate: NotifCard {
        required property var modelData
        row: page.svc.rowFor(modelData)
        svc: page.svc
        width: parent ? parent.width : 0
      }
    }
  }

  CcGroup {
    title: "Alerts"
    CcSwitchRow {
      title: "Crash notifications"
      subtitle: "Announce crashed programs and offer a diagnosis"
      checked: page.crashCapture
      onToggled: page.cc.runner.run(["omarchy-toggle-crash-capture"], function() { page.refresh() })
    }
    CcRow {
      title: "Send a test notification"
      subtitle: "With two actions and a reply box, to try the center"
      clickable: true
      onClicked: page.cc.runner.run(["notify-send", "-a", "Control Center", "-A", "ok=Looks good", "-A", "later=Later",
        "Test notification", "Notifications are working. Try an action, or dismiss me."], null)
    }
  }
}
