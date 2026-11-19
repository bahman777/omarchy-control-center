import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Services.UPower
import qs.Commons
import "quick"

// The Control Center's background service: peripheral batteries (always), and
// the notification daemon, used when you switch it on
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
      // Only hand back what we took — and if nothing else would show
      // notifications (no Dynamic Island), give them back to Omarchy.
      Quickshell.execDetached(["sh", "-c",
        "if [ -f \"$1\" ] || [ \"$4\" = none ]; then omarchy-plugin-enable omarchy.notifications; rm -f \"$1\"; fi; "
        + "if [ -f \"$2\" ]; then python3 -I \"$3\" true; rm -f \"$2\"; fi",
        "cc", markerPath, islandMarkerPath, pluginDir + "/tools/island-notifications.py", islandEntry ? "island" : "none"])
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

  // Mirror Do Not Disturb into Omarchy's notification state file while we own
  // notifications, so bar widgets that read it (and Omarchy, if it takes over
  // again later) agree with us. Only the "dnd" key changes.
  onDndChanged: mirrorDnd()
  onActiveChanged: mirrorDnd()
  function mirrorDnd() {
    if (!active) return
    Quickshell.execDetached(["python3", "-I", "-c",
      "import json,os,sys,tempfile\n"
      + "p=os.path.expanduser('~/.local/state/omarchy/notifications.json')\n"
      + "try:\n d=json.load(open(p))\nexcept Exception:\n d={'version':3}\n"
      + "if not isinstance(d,dict): d={'version':3}\n"
      + "v=sys.argv[1]=='true'\n"
      + "if d.get('dnd')!=v:\n"
      + " d['dnd']=v; os.makedirs(os.path.dirname(p),exist_ok=True)\n"
      + " fd,t=tempfile.mkstemp(dir=os.path.dirname(p))\n"
      + " f=os.fdopen(fd,'w'); json.dump(d,f,indent=2); f.write('\\n'); f.close(); os.replace(t,p)\n",
      dnd ? "true" : "false"])
  }

  // ------------------------------------------------------------ peripherals
  // Logitech Unifying/Bolt devices aren't Bluetooth and Linux exposes no
  // battery for them; Solaar reads it over HID++ (~6 s). Polled here in the
  // background and cached, so the Power page shows it at once and a sleeping
  // mouse keeps its last known level.
  property var peripherals: []        // [{model, kind, percent, status, source, seen}]
  readonly property string peripheralsPath: stateDir + "/peripherals.json"
  FileView {
    id: periphFile
    path: svc.peripheralsPath
    printErrors: false
    atomicWrites: true
    onLoaded: { try { var o = JSON.parse(text()); if (Array.isArray(o)) svc.peripherals = o } catch (e) {} }
  }
  Process {
    id: solaar
    command: ["timeout", "25", "solaar", "show"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: svc.parseSolaar(text)
    }
  }
  Timer { interval: 180000; running: true; repeat: true; triggeredOnStart: true; onTriggered: svc.refreshPeripherals() }
  function refreshPeripherals() { if (!solaar.running) solaar.running = true }
  // Other tools (e.g. a gadget-batteries plugin) poll Solaar too; two queries
  // at once collide on the receiver and battery lines come back empty. Retry
  // a few times at a random offset so we fall out of step with them.
  property int periphRetries: 0
  Timer { id: periphRetry; repeat: false; onTriggered: svc.refreshPeripherals() }
  function parseSolaar(out) {
    var found = [], cur = null
    String(out || "").split("\n").forEach(function(l) {
      var m = /^  (\d+): (.+)$/.exec(l)
      if (m) { cur = { model: m[2].trim().slice(0, 60), kind: "", percent: -1, status: "", source: "Logitech receiver" }; found.push(cur); return }
      if (!cur) return
      // The header name and the DEVICE NAME feature must agree; a mismatch
      // means another Solaar query spliced its reply in (names come in 16-byte
      // chunks), so the whole reading is treated as a collision.
      var nm = /^\s+Name:\s*(.+)$/.exec(l)
      if (nm && nm[1].trim().slice(0, 60) !== cur.model) cur.corrupt = true
      var k = /^\s+Kind\s*:\s*(\w+)/.exec(l)
      if (k && !cur.kind) cur.kind = k[1]
      var b = /Battery:\s*(\d+)%(?:,\s*BatteryStatus\.(\w+))?/.exec(l)
      if (b && cur.percent < 0) { cur.percent = Number(b[1]); cur.status = (b[2] || "").toLowerCase() }
    })
    var corrupt = found.some(function(d) { return d.corrupt })
    var gotReading = !corrupt && found.some(function(d) { return d.percent >= 0 })
    if (!gotReading && found.length > 0 && periphRetries < 3) {
      periphRetries++
      periphRetry.interval = 4000 + Math.floor(Math.random() * 9000)
      periphRetry.restart()
    } else if (gotReading) periphRetries = 0
    if (found.length === 0 || corrupt) return   // solaar missing, receiver busy or garbled: keep what we had
    var now = Date.now(), prev = {}
    peripherals.forEach(function(p) { prev[p.model] = p })
    var next = found.map(function(d) {
      if (d.percent >= 0) { d.seen = now; return d }
      // Asleep: keep the last reading, marked by when it was taken.
      var old = prev[d.model]
      if (old && old.percent >= 0) { d.percent = old.percent; d.status = old.status; d.seen = old.seen }
      return d
    }).filter(function(d) { return d.percent >= 0 })
    peripherals = next
    periphFile.setText(JSON.stringify(next) + "\n")
  }

  // ------------------------------------------------------------ battery alerts
  // Laptop, while unplugged: 20% (normal), 10% and 5% (critical).
  // Every other device (Bluetooth, phone, Logitech): 15% and 5% (critical).
  // Each level alerts once; charging, or gaining 10 points, re-arms it.
  // Sent through notify-send so they reach whichever daemon owns notifications.
  readonly property var laptopLevels: [20, 10, 5]
  readonly property var deviceLevels: [15, 5]
  property var alerted: ({})          // device key -> lowest level alerted
  readonly property string alertsPath: stateDir + "/battery-alerts.json"
  FileView {
    id: alertsFile
    path: svc.alertsPath
    printErrors: false
    atomicWrites: true
    onLoaded: { try { var o = JSON.parse(text()); if (o && typeof o === "object" && !Array.isArray(o)) svc.alerted = o } catch (e) {} }
  }
  // Omarchy's own 10% warning; dropped while these alerts run (see receive()).
  property string omarchyLowTitle: "Time to recharge!"
  Process {
    running: true
    command: ["omarchy-i18n", "battery.lowTitle"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { var t = String(text).trim(); if (t) svc.omarchyLowTitle = t } }
  }
  Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: svc.checkBatteries() }
  Connections { target: UPower; function onOnBatteryChanged() { svc.checkBatteries() } }

  function checkBatteries() {
    var d = UPower.displayDevice
    if (d && d.isPresent && d.percentage > 0)
      checkLevel("laptop", "Laptop", Math.round(d.percentage * 100), !UPower.onBattery, laptopLevels, true,
                 d.timeToEmpty > 0 ? d.timeToEmpty : 0)
    var devs = UPower.devices ? UPower.devices.values : []
    for (var i = 0; i < devs.length; i++) {
      var u = devs[i]
      if (!u || u.isLaptopBattery || !u.isPresent || u.type === UPowerDeviceType.LinePower || !u.model || !(u.percentage > 0)) continue
      checkLevel("upower:" + u.model, String(u.model), Math.round(u.percentage * 100),
                 u.state === UPowerDeviceState.Charging || u.state === UPowerDeviceState.FullyCharged, deviceLevels, false, 0)
    }
    peripherals.forEach(function(p) {
      checkLevel("solaar:" + p.model, p.model, p.percent, p.status === "recharging" || p.status === "full", svc.deviceLevels, false, 0)
    })
  }
  function checkLevel(key, name, pct, charging, levels, isLaptop, secsLeft) {
    var prev = alerted[key]
    if (charging || (prev !== undefined && pct >= prev + 10)) {
      if (prev !== undefined) { var r = Object.assign({}, alerted); delete r[key]; saveAlerts(r) }
      return
    }
    var hit = -1
    for (var i = 0; i < levels.length; i++) if (pct <= levels[i]) hit = levels[i]
    if (hit < 0 || (prev !== undefined && prev <= hit)) return
    var a = Object.assign({}, alerted); a[key] = hit; saveAlerts(a)
    sendBatteryAlert(name, pct, hit, isLaptop, secsLeft)
  }
  function saveAlerts(a) { alerted = a; alertsFile.setText(JSON.stringify(a) + "\n") }
  function sendBatteryAlert(name, pct, level, isLaptop, secsLeft) {
    var left = secsLeft > 0 ? " · about " + (secsLeft >= 3600 ? Math.floor(secsLeft / 3600) + " h " : "") + Math.round((secsLeft % 3600) / 60) + " min left" : ""
    var critical = !isLaptop || level <= 10
    var title, body
    if (isLaptop) {
      title = level <= 5 ? "Plug in now: battery at " + pct + "%" : level <= 10 ? "Battery very low: " + pct + "%" : "Battery low: " + pct + "%"
      body = (level <= 5 ? "Your laptop will shut down soon." : level <= 10 ? "Plug in soon." : "Time to find a charger.") + left
    } else {
      title = (level <= 5 ? "Almost empty: " : "Low battery: ") + name
      body = pct + "% left · " + (level <= 5 ? "charge it now" : "charge it soon")
    }
    Quickshell.execDetached(["notify-send", "-a", "Battery", "-u", critical ? "critical" : "normal",
      "-i", level <= 5 ? "battery-empty" : "battery-caution", "-t", critical ? "20000" : "10000", title, body])
  }

  // ------------------------------------------------------------ calendar
  // Events from tools/calendar.py (iCal links, cached for offline), refreshed
  // every 15 minutes; the panel and the Calendar page read calData.
  property var calData: ({ calendars: [], events: [], updated: 0 })
  property bool calBusy: false
  property var calQueued: null
  property var calOnDone: null
  Process {
    id: calProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var o = null
        try { o = JSON.parse(text) } catch (e) {}
        if (o && o.events) svc.calData = o
        var cb = svc.calOnDone; svc.calOnDone = null
        if (cb) cb(o)
      }
    }
    onExited: {
      svc.calBusy = false
      if (svc.calQueued) { var q = svc.calQueued; svc.calQueued = null; svc.calRun(q.args, q.done) }
    }
  }
  function calRun(args, done) {
    if (calProc.running) { calQueued = { args: args, done: done || null }; return }
    calOnDone = done || null
    // Arguments (private iCal links) go in the environment, readable only by
    // this account, not on the command line every local account can see.
    calProc.environment = { CC_CALENDAR_ARGS: JSON.stringify(args && args.length ? args : ["events"]) }
    calProc.command = ["python3", "-I", pluginDir + "/tools/calendar.py", "--args-from-env"]
    calBusy = true
    calProc.running = true
  }
  Timer { interval: 900000; running: true; repeat: true; triggeredOnStart: true; onTriggered: svc.calRun(["events"]) }

  // Reminder pop-up 10 minutes before each timed event (Join when it has a
  // Meet/Zoom/Teams link). Sent once per event, remembered across restarts.
  readonly property int remindLeadMs: 600000
  property var reminded: ({})
  FileView {
    id: remindedFile
    path: svc.stateDir + "/calendar-reminded.json"
    printErrors: false
    atomicWrites: true
    onLoaded: { try { var o = JSON.parse(text()); if (o && typeof o === "object") svc.reminded = o } catch (e) {} }
  }
  Timer {
    interval: 30000; running: true; repeat: true
    onTriggered: {
      var now = Date.now(), r = Object.assign({}, svc.reminded), changed = false
      var cals = {}
      ;(svc.calData.calendars || []).forEach(function(c) { cals[c.id] = c })
      ;(svc.calData.events || []).forEach(function(e) {
        if (e.allDay) return
        var lead = e.start - now
        if (lead > svc.remindLeadMs || lead < -60000) return
        var key = e.cal + "|" + e.uid + "|" + e.start
        if (r[key]) return
        r[key] = e.start; changed = true
        svc.sendEventReminder(e, Math.max(0, Math.round(lead / 60000)), (cals[e.cal] || {}).name || "")
      })
      for (var k in r) if (r[k] < now - 86400000) { delete r[k]; changed = true }
      if (changed) { svc.reminded = r; remindedFile.setText(JSON.stringify(r) + "\n") }
    }
  }
  function hm(ms) { return Qt.formatTime(new Date(ms), "h:mm AP") }
  function sendEventReminder(e, mins, calName) {
    var title = (mins <= 0 ? "Starting now: " : "In " + mins + " min: ") + e.title
    var body = hm(e.start) + " – " + hm(e.end) + (e.location && !e.join ? " · " + e.location : "") + (calName ? " · " + calName : "")
    // Title, details and link go in the environment (only this account can
    // read it), not on notify-send's command line (every account can).
    Quickshell.execDetached({
      command: ["python3", "-I", pluginDir + "/tools/remind.py"],
      environment: { CC_REMINDER: JSON.stringify({ title: title, body: body, join: e.join || "" }) }
    })
  }

  // ------------------------------------------------------------ night light
  // "Sunset to sunrise" times drift with the seasons: re-apply once a day,
  // around midday, so a reload never undoes an evening on/off.
  Timer {
    interval: 3600000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: {
      var h = new Date().getHours()
      if (h >= 10 && h < 16) Quickshell.execDetached(["timeout", "60", "python3", "-I", svc.pluginDir + "/tools/nightlight.py", "apply"])
    }
  }

  // ------------------------------------------------------------ server
  property var arrival: ({})        // id -> ms
  property var popupIds: []         // newest first
  property var popupUntil: ({})     // id -> ms (0 = until dismissed)
  // Hovering pauses only the pop-up under the pointer; leaving gives it a few
  // more seconds. Nothing stays longer than maxLifeMs, hover or not.
  property int hoverId: -1
  readonly property int maxLifeMs: 30000
  function hover(id, on) {
    if (on) { hoverId = id; return }
    if (hoverId !== id) return
    hoverId = -1
    var u = Object.assign({}, popupUntil); u[id] = Math.max(u[id] || 0, Date.now() + 2500); popupUntil = u
  }

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
    // Our battery alerts cover Omarchy's single 10% warning; don't show both.
    if (String(n.summary || "") === omarchyLowTitle) { n.dismiss(); return }
    n.tracked = true
    var a = {}; for (var k in arrival) a[k] = arrival[k]; a[n.id] = Date.now(); arrival = a
    if (dnd && n.urgency !== NotificationUrgency.Critical) return
    // Every pop-up times out (it stays in the panel's list until cleared).
    // Senders give milliseconds (notify-send -t 8000); a value that large is
    // read as ms. "Never" or none → 6 s; capped at 10 s; urgent ones get 20 s.
    var t = Number(n.expireTimeout) || 0
    if (t > 300) t = t / 1000
    var secs = n.urgency === NotificationUrgency.Critical ? 20 : t > 0 ? Math.min(10, Math.max(3, t)) : 6
    var u = {}; for (var j in popupUntil) u[j] = popupUntil[j]
    u[n.id] = Date.now() + secs * 1000
    popupUntil = u
    popupIds = [n.id].concat(popupIds.filter(function(x) { return x !== n.id })).slice(0, 4)
  }

  function byId(id) {
    for (var i = 0; i < tracked.length; i++) if (tracked[i] && tracked[i].id === id) return tracked[i]
    return null
  }

  // ------------------------------------------------------------ history
  // The list survives shell restarts: rows are saved (newest 50, mode 600)
  // and come back as "archived" rows, with no actions or reply, since their
  // sender can't be reached any more. Image-provider URLs don't survive a
  // restart either, so only file images are kept.
  readonly property string historyPath: stateDir + "/notification-history.json"
  property var archived: []
  property bool historyLoaded: false
  Process {
    running: true
    command: ["sh", "-c", "umask 077; mkdir -p \"$1\"; [ -e \"$2\" ] || echo '[]' > \"$2\"; chmod 600 \"$2\"", "sh", svc.stateDir, svc.historyPath]
    onExited: historyFile.reload()
  }
  FileView {
    id: historyFile
    path: svc.historyPath
    printErrors: false
    onLoaded: {
      if (svc.historyLoaded) return
      var list = []
      try { list = JSON.parse(text()) || [] } catch (e) { list = [] }
      svc.archived = list.slice(0, 50).map(function(r, i) {
        return { id: "a" + i + "-" + (r.time || 0), appName: String(r.appName || ""), appIcon: String(r.appIcon || ""),
                 image: String(r.image || ""), summary: String(r.summary || ""), body: String(r.body || ""),
                 urgency: Number(r.urgency) || 1, actions: [], hasDefault: false, hasReply: false,
                 replyPlaceholder: "", time: Number(r.time) || 0, archived: true }
      })
      svc.historyLoaded = true
    }
  }
  Timer { id: historySave; interval: 1000; onTriggered: svc.saveHistory() }
  onRowsChanged: if (historyLoaded) historySave.restart()
  function saveHistory() {
    var out = rows.slice(0, 50).map(function(r) {
      var img = String(r.image || "")
      return { appName: r.appName, appIcon: r.appIcon, image: img.indexOf("/") === 0 || img.indexOf("file:") === 0 ? img : "",
               summary: r.summary, body: r.body, urgency: r.urgency, time: r.time }
    })
    historyFile.setText(JSON.stringify(out) + "\n")
  }

  // Plain snapshots for the UI, newest first.
  readonly property var rows: {
    var list = archived.slice()
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
  // A row by id, for lists that keep their delegates by id (so a reply being
  // typed survives other notifications coming and going); a blank row while
  // the list catches up after one is removed.
  function rowFor(id) {
    for (var i = 0; i < rows.length; i++) if (rows[i].id === id) return rows[i]
    return { id: id, appName: "", appIcon: "", image: "", summary: "", body: "", urgency: 1,
             actions: [], hasDefault: false, hasReply: false, replyPlaceholder: "", time: 0 }
  }
  // Ids only, reassigned only when the set or order changes.
  function keysOf(list, old) {
    var k = list.map(function(r) { return r.id })
    return (old && k.join("|") === old.join("|")) ? old : k
  }
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
        var until = svc.popupUntil[id] || 0
        var born = svc.arrival[id] || now
        var paused = svc.hoverId === id && now - born < svc.maxLifeMs
        if (now > until && !paused) {
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
    if (typeof id === "string") { archived = archived.filter(function(r) { return r.id !== id }); return }
    var n = byId(id)
    hidePopup(id)
    if (n) n.dismiss()
  }
  function clearAll() {
    archived = []
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
    // Preview the battery alerts without waiting for a battery to drain.
    // Preview a meeting reminder using the next event that has a join link.
    function calendarPreview(): string {
      var now = Date.now(), evs = (svc.calData.events || []).filter(function(e) { return !e.allDay && e.end > now })
      var e = evs.filter(function(x) { return x.join })[0] || evs[0]
      if (!e) return "no upcoming events"
      svc.sendEventReminder(e, 10, ""); return "ok"
    }
    function batteryPreview(): string { svc.sendBatteryAlert("Laptop", 9, 10, true, 1500); svc.sendBatteryAlert("Mobi Fold for Business", 14, 15, false, 0); return "ok" }
    function invokeLast(): string { if (!svc.rows.length) return "none"; svc.activate(svc.rows[0].id); return "ok" }
    function invokeAction(n: int): string {
      if (!svc.popupIds.length) return "none"
      var r = svc.popupRows[0]
      if (!r || n < 1 || n > r.actions.length) return "none"
      svc.invoke(r.id, r.actions[n - 1].id)
      return "ok"
    }
    // Omarchy binds Super + Ctrl + , to this ("control notifications with the
    // keyboard"): open or close Quick Settings, which is fully keyboard driven.
    function keyboard(): string {
      Quickshell.execDetached(["omarchy-shell", "control-center", "toggle"])
      return "ok"
    }
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
    // Pop-ups never take the keyboard (and the mode is never switched at run
    // time: that remaps the surface and loses hover/clicks). Replies are typed
    // in the Quick Settings list instead.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

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
