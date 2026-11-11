import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import qs.Commons
import "quick"

// The Control Center's notification daemon, used when you switch it on
// (Notifications page → "Use Quick Settings for notifications").
//
// Only one program can own notifications. Like Dynamic Island, this takes the
// job over from Omarchy's own service (disabling omarchy.notifications and
// leaving a marker so it knows it did) and hands it back when switched off.
// It answers the same `omarchy-shell notifications ...` commands, so Omarchy's
// keybindings and `omarchy toggle notification silencing` keep working.
Scope {
  id: svc

  // Injected by the shell.
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/control-center"
  readonly property string settingsPath: stateDir + "/notifications.json"
  readonly property string markerPath: stateDir + "/notifications-takeover"
  readonly property string islandMarkerPath: stateDir + "/island-notifications-handed"
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

  // ------------------------------------------------------------ settings
  property bool wants: false
  property bool dnd: false
  property bool settingsLoaded: false

  FileView {
    id: settingsFile
    path: svc.settingsPath
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        var o = JSON.parse(text())
        svc.wants = o.enabled === true
        svc.dnd = o.dnd === true
      } catch (e) {}
      svc.settingsLoaded = true
    }
    onLoadFailed: svc.settingsLoaded = true
  }
  function saveSettings() {
    settingsFile.setText(JSON.stringify({ enabled: wants, dnd: dnd }, null, 2) + "\n")
  }
  Process { running: true; command: ["mkdir", "-p", svc.stateDir] }

  // ------------------------------------------------------------ ownership
  property var disabledPlugins: []
  property var islandEntry: null
  property bool shellLoaded: false
  FileView {
    path: svc.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var o = JSON.parse(text())
        svc.disabledPlugins = Array.isArray(o.disabledPlugins) ? o.disabledPlugins : []
        var isl = null
        ;(o.plugins || []).forEach(function(p) { if (p && p.id === "omarchy-dynamic-island") isl = p })
        svc.islandEntry = isl
      } catch (e) {}
      svc.shellLoaded = true
    }
  }
  readonly property bool omarchyOff: disabledPlugins.indexOf("omarchy.notifications") >= 0
  readonly property bool islandOwns: !!islandEntry && islandEntry.notifications !== false
    && disabledPlugins.indexOf("omarchy-dynamic-island") < 0
  readonly property bool wantActive: wants && omarchyOff && !islandOwns
  property bool active: false
  // Who handles notifications right now, for the UI.
  readonly property string owner: active ? "control-center" : islandOwns ? "island" : !omarchyOff ? "omarchy" : (wants ? "starting" : "none")

  // Let the previous owner release the bus before ours starts.
  onWantActiveChanged: settle.restart()
  Timer { id: settle; interval: 1500; onTriggered: svc.active = svc.wantActive }

  onWantsChanged: sync()
  onIslandOwnsChanged: sync()
  onOmarchyOffChanged: sync()
  onShellLoadedChanged: sync()
  onSettingsLoadedChanged: sync()

  function sync() {
    if (!settingsLoaded || !shellLoaded) return
    if (wants) {
      if (islandOwns) {
        // Ask the island to let go (remembering we did), then take over from Omarchy.
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\" && python3 -I \"$2\" false",
          "cc", islandMarkerPath, pluginDir + "/tools/island-notifications.py"])
      } else if (!omarchyOff) {
        Quickshell.execDetached(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && touch \"$1\" && omarchy-plugin-disable omarchy.notifications",
          "cc", markerPath])
      }
    } else {
      // Only hand back what we took.
      Quickshell.execDetached(["sh", "-c",
        "if [ -f \"$1\" ]; then omarchy-plugin-enable omarchy.notifications; rm -f \"$1\"; fi; "
        + "if [ -f \"$2\" ]; then python3 -I \"$3\" true; rm -f \"$2\"; fi",
        "cc", markerPath, islandMarkerPath, pluginDir + "/tools/island-notifications.py"])
    }
  }

  function setEnabled(value) {
    wants = value === true
    saveSettings()
  }
  function setDnd(value) {
    dnd = value === true
    saveSettings()
    if (dnd) popupIds = popupIds.filter(function(id) { var n = byId(id); return n && n.urgency === NotificationUrgency.Critical })
  }

  // ------------------------------------------------------------ server
  property var arrival: ({})        // id -> ms
  property var popupIds: []         // newest first
  property var popupUntil: ({})     // id -> ms (0 = until dismissed)
  property bool held: false
  function hold(on) { held = on }

  LazyLoader {
    id: serverLoader
    active: svc.active
    NotificationServer {
      keepOnReload: false
      actionsSupported: true
      actionIconsSupported: false
      imageSupported: true
      // Plain text everywhere: nothing a sender writes is rendered as markup.
      bodyMarkupSupported: false
      bodyHyperlinksSupported: false
      bodyImagesSupported: false
      inlineReplySupported: true
      persistenceSupported: true
      onNotification: function(n) { svc.receive(n) }
    }
  }
  readonly property var server: serverLoader.item
  readonly property var tracked: server && server.trackedNotifications ? server.trackedNotifications.values : []

  function receive(n) {
    n.tracked = true
    var a = {}; for (var k in arrival) a[k] = arrival[k]; a[n.id] = Date.now(); arrival = a
    if (dnd && n.urgency !== NotificationUrgency.Critical) return
    var secs = n.expireTimeout > 0 ? n.expireTimeout : 6
    var u = {}; for (var j in popupUntil) u[j] = popupUntil[j]
    u[n.id] = n.urgency === NotificationUrgency.Critical ? 0 : Date.now() + secs * 1000
    popupUntil = u
    popupIds = [n.id].concat(popupIds.filter(function(x) { return x !== n.id })).slice(0, 4)
  }

  function byId(id) {
    for (var i = 0; i < tracked.length; i++) if (tracked[i] && tracked[i].id === id) return tracked[i]
    return null
  }

  // Plain snapshots for the UI, newest first.
  readonly property var rows: {
    var list = []
    for (var i = 0; i < tracked.length; i++) {
      var n = tracked[i]
      if (!n) continue
      var acts = [], hasDefault = false
      var al = n.actions || []
      for (var j = 0; j < al.length; j++) {
        var id = String(al[j].identifier || "")
        if (id === "default") { hasDefault = true; continue }
        acts.push({ id: id, text: String(al[j].text || id).slice(0, 40) })
      }
      list.push({
        id: n.id, appName: String(n.appName || "").slice(0, 60), appIcon: String(n.appIcon || ""),
        image: String(n.image || ""), summary: String(n.summary || "").slice(0, 300),
        body: String(n.body || "").slice(0, 2000), urgency: n.urgency === NotificationUrgency.Critical ? 2 : n.urgency === NotificationUrgency.Low ? 0 : 1,
        actions: acts.slice(0, 4), hasDefault: hasDefault, hasReply: !!n.hasInlineReply,
        replyPlaceholder: String(n.inlineReplyPlaceholder || ""), time: arrival[n.id] || Date.now()
      })
    }
    list.sort(function(a, b) { return b.time - a.time })
    return list
  }
  readonly property int count: rows.length
  readonly property var popupRows: rows.filter(function(r) { return svc.popupIds.indexOf(r.id) >= 0 })

  // Drop popups whose notification went away, and time the rest out.
  Timer {
    interval: 250
    repeat: true
    running: svc.popupIds.length > 0
    onTriggered: {
      var now = Date.now(), keep = []
      for (var i = 0; i < svc.popupIds.length; i++) {
        var id = svc.popupIds[i], n = svc.byId(id)
        if (!n) continue
        var until = svc.popupUntil[id]
        if (until && now > until && !svc.held) {
          if (n.transient) n.expire()
          continue
        }
        keep.push(id)
      }
      if (keep.length !== svc.popupIds.length) svc.popupIds = keep
    }
  }

  // ------------------------------------------------------------ actions
  function hidePopup(id) { popupIds = popupIds.filter(function(x) { return x !== id }) }
  function dismiss(id) {
    var n = byId(id)
    hidePopup(id)
    if (n) n.dismiss()
  }
  function clearAll() {
    var all = tracked.slice()
    popupIds = []
    for (var i = 0; i < all.length; i++) if (all[i]) all[i].dismiss()
  }
  function invoke(id, actionId) {
    var n = byId(id)
    if (!n) return
    var al = n.actions || []
    for (var i = 0; i < al.length; i++) if (String(al[i].identifier) === actionId) { al[i].invoke(); break }
    hidePopup(id)
    if (!n.resident && n.tracked) n.dismiss()
  }
  // A click: the sender's default action if it has one, then the card goes.
  function activate(id) {
    var n = byId(id)
    if (!n) return
    var al = n.actions || []
    for (var i = 0; i < al.length; i++) if (String(al[i].identifier) === "default") { invoke(id, "default"); return }
    hidePopup(id)
  }
  function reply(id, text) {
    var n = byId(id)
    var t = String(text || "").trim()
    if (!n || t === "") return
    n.sendInlineReply(t)
    hidePopup(id)
  }

  // ------------------------------------------------------------ Omarchy's IPC
  ShellIpc {
    target: "notifications"
    enabled: svc.active

    function ping(): string { return "ok" }
    function isDnd(): string { return svc.dnd ? "on" : "off" }
    function toggleDnd(): string { svc.setDnd(!svc.dnd); return isDnd() }
    function setDnd(value: string): string {
      var v = String(value || "").toLowerCase()
      svc.setDnd(v === "true" || v === "1" || v === "on" || v === "yes")
      return isDnd()
    }
    function act(): string { if (!svc.popupIds.length) return "none"; svc.activate(svc.popupIds[0]); return "ok" }
    function dismissOne(): string { if (!svc.popupIds.length) return "none"; svc.dismiss(svc.popupIds[0]); return "ok" }
    function dismissAll(): string { svc.clearAll(); return "ok" }
    function invokeLast(): string { if (!svc.rows.length) return "none"; svc.activate(svc.rows[0].id); return "ok" }
    function invokeAction(n: int): string {
      if (!svc.popupIds.length) return "none"
      var r = svc.popupRows[0]
      if (!r || n < 1 || n > r.actions.length) return "none"
      svc.invoke(r.id, r.actions[n - 1].id)
      return "ok"
    }
    function keyboard(): string { return "none" }
    function showHistory(): string {
      Quickshell.execDetached(["omarchy-shell", "control-center", "settings", "notifications"])
      return "ok"
    }
    function dismiss(summary: string): string {
      var needle = String(summary || "")
      if (!needle) return "none"
      var hit = svc.rows.filter(function(r) { return r.summary.indexOf(needle) !== -1 })
      hit.forEach(function(r) { svc.dismiss(r.id) })
      return hit.length ? "ok" : "none"
    }
  }

  // ------------------------------------------------------------ pop-ups
  PanelWindow {
    id: popupWindow
    visible: svc.active && svc.popupRows.length > 0
    screen: {
      var m = Hyprland.focusedMonitor
      for (var i = 0; i < Quickshell.screens.length; i++)
        if (m && Quickshell.screens[i].name === m.name) return Quickshell.screens[i]
      return Quickshell.screens.length ? Quickshell.screens[0] : null
    }
    anchors { top: true; right: true }
    margins.top: Style.gapsOut
    margins.right: Style.gapsOut * 2
    color: "transparent"
    implicitWidth: Style.space(400)
    implicitHeight: Math.max(1, stack.implicitHeight)
    WlrLayershell.namespace: "control-center-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Column {
      id: stack
      width: parent.width
      spacing: Style.space(8)
      Repeater {
        model: svc.popupRows
        delegate: NotifCard {
          required property var modelData
          row: modelData
          svc: svc
          popup: true
          compact: true
          width: stack.width
        }
      }
    }
  }
}
