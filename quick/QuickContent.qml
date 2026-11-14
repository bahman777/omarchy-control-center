import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "../Icons.js" as Icons
import "../Pages.js" as Pages
import "../ui"

// GNOME-style Quick Settings: header buttons, sliders, and a grid of pill
// toggles whose menus open in place. Lives only while the panel is open, so
// all polling stops when it closes.
Item {
  id: q

  // The bar widget (BarWidget.qml): runner, hypr, close(), launch() and the
  // `cc` API the settings pages use.
  required property var qc

  // The outer Flickable, so the keyboard cursor can scroll items into view.
  property var flick: null

  implicitHeight: page === "" ? col.implicitHeight : pageView.implicitHeight
  property string expanded: ""
  // ------------------------------------------------------------ transitions
  // Going deeper (a menu, a page) slides the new view in from the right;
  // going back slides it in from the left. Short and small: just enough to
  // follow where you went.
  property int navDir: 1
  function slideIn(view) {
    if (!view || !view.visible || !q.qc.opened) return
    navAnim.stop()
    navAnim.target = view
    navAnim.dx = q.navDir * Style.space(36)
    navAnim.start()
  }
  ParallelAnimation {
    id: navAnim
    property Item target: null
    property real dx: 0
    NumberAnimation { target: navAnim.target; property: "x"; from: navAnim.dx; to: 0; duration: Style.duration(200); easing.type: Easing.OutCubic }
    NumberAnimation { target: navAnim.target; property: "opacity"; from: 0.25; to: 1; duration: Style.duration(170); easing.type: Easing.OutCubic }
    onStopped: if (target) { target.x = 0; target.opacity = 1 }
  }
  function currentView() { return page !== "" ? pageView : expanded !== "" ? menuView : col }

  function toggleMenu(id) {
    navDir = expanded === id ? -1 : 1
    expanded = expanded === id ? "" : id
    if (flick) flick.contentY = 0
    resetCursor()
  }

  // ------------------------------------------------------------ in-panel pages
  // Settings open inside the panel as a page with a back button; nothing jumps
  // out to another window.
  property var pageStack: []
  readonly property string page: pageStack.length ? pageStack[pageStack.length - 1] : ""
  readonly property var pageInfo: page === "index" ? { title: "Settings", icon: Icons.cog } : (Pages.find(page) || { title: "", icon: "" })
  function openPage(id) {
    navDir = 1
    var target = id && (id === "index" || Pages.find(id)) ? id : "index"
    pageStack = pageStack.concat([target])
    expanded = ""
    resetCursor()
  }
  function back() {
    navDir = -1
    pageStack = pageStack.slice(0, -1)
    resetCursor()
  }
  onPageChanged: { qc.pageMode = page !== ""; if (flick) flick.contentY = 0; Qt.callLater(function() { q.slideIn(q.currentView()) }) }

  // IPC / right-click requests: "wifi" expands a menu, "page:sound" opens a page.
  function applyRequest(req) {
    if (!req) return
    // Menus whose tiles moved to settings pages open those pages instead.
    var moved = { printers: "printers", scanners: "printers", layout: "windows", wired: "network" }
    if (req.indexOf("page:") === 0) { pageStack = []; openPage(req.slice(5)) }
    else if (moved[req]) { pageStack = []; openPage(moved[req]) }
    else { pageStack = []; expanded = req }
  }
  Component.onCompleted: {
    qc.pageOpener = openPage
    qc.nightToggle = function(on) { q.nightOn = on; q.nightApply(on) }
    applyRequest(qc.menu)
  }
  Connections {
    target: q.qc
    function onMenuChanged() { q.applyRequest(q.qc.menu) }
    // A plain click on the bar always opens the main panel: no page or menu
    // left over from last time (the shell may keep this content alive).
    function onOpenedChanged() { if (q.qc.opened && !q.qc.menu) { q.pageStack = []; q.expanded = ""; q.resetCursor() } }
  }

  // Esc: leave the page, then collapse the menu, then close the panel.
  function stepBack() {
    navDir = -1
    if (page !== "") back()
    else if (expanded !== "") { expanded = ""; resetCursor() }
    else qc.close()
  }

  // ------------------------------------------------------------ keyboard cursor
  // Items opt in with `ccFocusable`, `hasCursor` and `ccActivate()`; sliders
  // and choice rows add `ccAdjust(dir)` for Left/Right. Arrows move by
  // geometry, Tab walks in order, so pages need no wiring of their own.
  property Item cursor: null
  property point lastCursorPos: Qt.point(0, 0)

  function resetCursor() { setCursor(null) }
  function setCursor(it) {
    if (cursor && cursor !== it) cursor.hasCursor = false
    cursor = it
    if (it) {
      it.hasCursor = true
      lastCursorPos = centerOf(it)
      ensureVisible(it)
    }
  }
  function centerOf(it) { return it.mapToItem(q, it.width / 2, it.height / 2) }
  function collect(item, out) {
    if (!item || !item.visible || item.opacity === 0) return
    if (item !== q && item.ccFocusable === true && typeof item.ccActivate === "function") out.push(item)
    var ch = item.children
    for (var i = 0; i < ch.length; i++) collect(ch[i], out)
  }
  function focusables() { var out = []; collect(q, out); return out }

  function moveCursor(dx, dy) {
    var items = focusables()
    if (items.length === 0) return
    if (!cursor || items.indexOf(cursor) < 0) {
      // Dormant until the first key; resume near where it was.
      var start = items[0], bestD = 1e9
      if (cursor === null && lastCursorPos.y > 0) {
        for (var k = 0; k < items.length; k++) {
          var pk = centerOf(items[k]), d = Math.abs(pk.x - lastCursorPos.x) + Math.abs(pk.y - lastCursorPos.y)
          if (d < bestD) { bestD = d; start = items[k] }
        }
      }
      setCursor(start)
      return
    }
    if (dx !== 0 && typeof cursor.ccAdjust === "function" && cursor.ccAdjust(dx)) return
    var c = centerOf(cursor), best = null, bestScore = 1e9
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (it === cursor) continue
      var p = centerOf(it), ddx = p.x - c.x, ddy = p.y - c.y, score
      if (dy !== 0) {
        if (ddy * dy <= 4) continue
        score = Math.abs(ddy) + Math.abs(ddx) * 1.5
      } else {
        if (ddx * dx <= 4 || Math.abs(ddy) > Math.max(cursor.height, it.height) / 2) continue
        score = Math.abs(ddx)
      }
      if (score < bestScore) { bestScore = score; best = it }
    }
    if (best) setCursor(best)
  }
  function stepCursor(dir) {
    var items = focusables()
    if (items.length === 0) return
    var idx = cursor ? items.indexOf(cursor) : -1
    idx = idx < 0 ? (dir > 0 ? 0 : items.length - 1) : (idx + dir + items.length) % items.length
    setCursor(items[idx])
  }
  function activateCursor() {
    if (!cursor) { moveCursor(0, 1); return }
    var it = cursor
    it.ccActivate()
  }
  function ensureVisible(it) {
    if (!flick) return
    var top = it.mapToItem(q, 0, 0).y, m = Style.space(12)
    if (top - m < flick.contentY) flick.contentY = Math.max(0, top - m)
    else if (top + it.height + m > flick.contentY + flick.height)
      flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), top + it.height + m - flick.height)
  }

  readonly property color fg: Color.menu.text
  function dimText(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }

  // ================================================================ Wi-Fi / wired
  readonly property var netDevices: Networking.devices ? Networking.devices.values : []
  function deviceOf(type) {
    var fallback = null
    for (var i = 0; i < netDevices.length; i++) {
      var d = netDevices[i]
      if (!d || d.type !== type) continue
      if (d.connected) return d
      if (!fallback) fallback = d
    }
    return fallback
  }
  readonly property var wifiDevice: deviceOf(DeviceType.Wifi)
  readonly property var wiredDevice: deviceOf(DeviceType.Wired)
  readonly property var wifiObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  // Primitive rows only (see pages/WifiPage.qml).
  readonly property var wifiRows: {
    var list = []
    for (var i = 0; i < wifiObjects.length; i++) {
      var n = wifiObjects[i]
      if (!n || !n.name) continue
      list.push({ ssid: String(n.name), connected: !!n.connected, known: !!n.known, signal: n.signalStrength || 0,
                  secure: n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe, changing: !!n.stateChanging })
    }
    list.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return b.signal - a.signal
    })
    return list
  }
  readonly property var wifiConnected: wifiRows.length > 0 && wifiRows[0].connected ? wifiRows[0] : null
  function wifiObject(ssid) {
    for (var i = 0; i < wifiObjects.length; i++) if (wifiObjects[i] && wifiObjects[i].name === ssid) return wifiObjects[i]
    return null
  }
  property string passwordFor: ""
  Binding { target: q.wifiDevice; property: "scannerEnabled"; value: true; when: q.wifiDevice !== null && q.expanded === "wifi" }
  Component.onDestruction: {
    if (wifiDevice) wifiDevice.scannerEnabled = false
    if (btAdapter && btAdapter.discovering) btAdapter.discovering = false
  }

  // ================================================================ Bluetooth
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btOn: !!btAdapter && btAdapter.enabled
  readonly property var btRows: {
    var list = []
    var devs = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devs.length; i++) {
      var d = devs[i]
      if (!d || !(d.paired || d.bonded || d.connected)) continue
      list.push({ address: String(d.address), name: String(d.name || d.deviceName || d.address), icon: String(d.icon || ""),
                  connected: !!d.connected, battery: d.batteryAvailable ? Math.round(d.battery * 100) : -1,
                  busy: d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting })
    }
    list.sort(function(a, b) { return a.connected !== b.connected ? (a.connected ? -1 : 1) : a.name.localeCompare(b.name) })
    return list
  }
  readonly property var btConnected: btRows.filter(function(r) { return r.connected })
  property var btPending: ({})
  function btAct(row, action) {
    var p = {}; for (var k in btPending) p[k] = btPending[k]; p[row.address] = action; btPending = p
    qc.runner.run(["omarchy-bluetooth-device", action, row.address], function() {
      var n = {}; for (var k in q.btPending) if (k !== row.address) n[k] = q.btPending[k]; q.btPending = n
    })
  }

  // ================================================================ Audio
  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var pwNames: pwNodes.map(function(n) { return n ? String(n.name || "") : "" })
  function pwHidden(n) {
    var name = String(n.name || "")
    return name.indexOf("omarchy_speaker_tuning") === 0 || AudioNodes.isShellLevelMeter(name) || AudioNodes.platformHides(name, pwNames)
  }
  readonly property var sinks: pwNodes.filter(function(n) { return n && n.isSink && !n.isStream && n.audio && !q.pwHidden(n) })
  readonly property var sources: pwNodes.filter(function(n) { return n && !n.isSink && !n.isStream && n.audio && !q.pwHidden(n) && String(n.name || "").indexOf(".monitor") < 0 })
  readonly property var defaultSink: Pipewire.defaultAudioSink
  readonly property var defaultSource: Pipewire.defaultAudioSource
  property string volumeSinkName: ""
  readonly property var volumeSink: {
    for (var i = 0; i < sinks.length; i++) if (sinks[i].name === volumeSinkName) return sinks[i]
    return defaultSink
  }
  onDefaultSinkChanged: sinkResolve.restart()
  // omarchy-audio-output-sink resolves a DSP output (speaker tuning, EasyEffects,
  // a filter chain) to the device it feeds. Only ask it about those: for any
  // other virtual sink it matches streams by name prefix, and a client stream
  // that happens to share the sink's name (snapclient's "Snapcast") would make
  // the speakers look selected.
  function isDspSink(name) {
    return /^(effect_input\.|omarchy_speaker_tuning|easyeffects_sink)/.test(String(name || ""))
  }
  Timer { id: sinkResolve; interval: 150; running: true
    onTriggered: {
      var name = q.defaultSink ? String(q.defaultSink.name || "") : ""
      if (!q.isDspSink(name)) { q.volumeSinkName = name; return }
      q.qc.runner.run(["omarchy-audio-output-sink"], function(code, out) { q.volumeSinkName = String(out).trim() })
    }
  }
  // Another output still playing while a different one is selected: the
  // laptop speakers carrying this machine's share of a Snapcast group, say.
  // Its volume isn't the main slider's, so it gets a small slider of its own.
  readonly property var alsoPlayingSink: {
    var groups = Pipewire.linkGroups ? Pipewire.linkGroups.values : []
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i]
      if (!g || !g.source || !g.target) continue
      var t = g.target
      if (!g.source.isStream || !t.isSink || t.isStream) continue
      if ((defaultSink && t.id === defaultSink.id) || (volumeSink && t.id === volumeSink.id)) continue
      if (sinks.indexOf(t) < 0) continue   // hidden: tuning chains, level meters
      return t
    }
    return null
  }
  readonly property real alsoVolume: alsoPlayingSink && alsoPlayingSink.audio ? alsoPlayingSink.audio.volume : 0
  readonly property bool alsoMuted: !!(alsoPlayingSink && alsoPlayingSink.audio && alsoPlayingSink.audio.muted)

  // Apps playing sound (per-app volume in the Sound menu).
  readonly property var streams: pwNodes.filter(function(n) { return n && n.isStream && n.isSink && n.audio && !q.pwHidden(n) })
  PwObjectTracker { objects: q.sinks.concat(q.sources).concat(q.expanded === "sound" ? q.streams : []) }
  function streamName(n) {
    var pr = n && n.properties ? n.properties : {}
    return String(pr["application.name"] || nodeLabel(n) || "App")
  }

  // Displays, from Hyprland (for the Displays tile and menu).
  property var displays: []
  property string laptopName: ""
  readonly property var displaysOn: displays.filter(function(m) { return !m.disabled })
  function nodeLabel(n) { return n ? String(n.description || n.nickname || n.name || "") : "" }
  function nodeIcon(n, input) {
    var s = (nodeLabel(n) + " " + String(n ? n.name : "")).toLowerCase()
    if (s.indexOf("bluez") >= 0 || s.indexOf("headset") >= 0) return Icons.headset
    if (s.indexOf("headphone") >= 0) return Icons.headphones
    if (s.indexOf("hdmi") >= 0 || s.indexOf("displayport") >= 0) return Icons.monitor
    return input ? Icons.microphone : Icons.speaker
  }
  readonly property real volume: volumeSink && volumeSink.audio ? volumeSink.audio.volume : 0
  readonly property bool volumeMuted: !!(volumeSink && volumeSink.audio && volumeSink.audio.muted)
  function volumeIcon() {
    if (volumeMuted || volume <= 0.001) return String.fromCodePoint(0xF075F)
    if (volume < 0.34) return String.fromCodePoint(0xF057F)
    if (volume < 0.67) return String.fromCodePoint(0xF0580)
    return Icons.volume
  }

  // ================================================================ Brightness
  property real brightness: -1
  property real pendingBrightness: -1
  Timer {
    id: brightnessApply
    interval: 90
    onTriggered: if (q.pendingBrightness >= 0)
      q.qc.runner.run(["omarchy-brightness-display", "--no-osd", Math.max(1, Math.round(q.pendingBrightness * 100)) + "%"], null)
  }

  // ================================================================ Battery / power
  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: !!battery && battery.isPresent
  property var profiles: []
  property string profile: ""
  // Read through Omarchy's own commands: the shell's first-party services
  // aren't exposed to bar widgets, and the CLIs keep the shell in sync.
  property bool stayAwake: false
  property bool nightOn: false
  // Night Light schedule and look, from tools/nightlight.py (writes hyprsunset.conf).
  property var nl: ({})
  readonly property string nlTool: Qt.resolvedUrl("../tools/nightlight.py").toString().replace(/^file:\/\//, "").replace(/\?.*$/, "")
  // One status check at a time, each capped, so a check that hangs can't
  // pile up helpers under the 4-second refresh.
  property bool nlChecking: false
  function refreshNight() {
    if (nlChecking) return
    nlChecking = true
    qc.runner.run(["timeout", "10", "python3", "-I", nlTool, "status"], function(code, out) {
      q.nlChecking = false
      try { q.nl = JSON.parse(out) } catch (e) {}
    })
  }
  function nightSet(args) {
    // Optimistic: show the change now, then read back what was applied.
    var n = Object.assign({}, nl)
    args.forEach(function(a) { var i = a.indexOf("="); var k = a.slice(0, i), v = a.slice(i + 1); n[k] = k === "temp" || k === "dim" ? Number(v) : v })
    nl = n
    qc.runner.run(["python3", "-I", nlTool, "set"].concat(args), function(code, out) {
      try { q.nl = JSON.parse(out) } catch (e) {}
      q.refreshSlow()
    })
  }
  // On/off now (the schedule takes over again at its next switch time).
  function nightApply(on) {
    var t = String(nl.temp || 4500), g = String(nl.dim || 100)
    qc.runner.run(["bash", "-c",
      'pgrep -x hyprsunset >/dev/null || { systemd-run --user --collect --quiet -- hyprsunset; sleep 1.5; }; '
      + 'if [ "$1" = on ]; then hyprctl hyprsunset temperature "$2"; hyprctl hyprsunset gamma "$3"; '
      + 'else hyprctl hyprsunset temperature 6500; hyprctl hyprsunset identity; hyprctl hyprsunset gamma 100; fi >/dev/null; omarchy-shell -q nightlight refresh',
      "nl", on ? "on" : "off", t, g], function() { q.refreshSlow() })
  }
  function hm12(hm) {
    var p = String(hm || "").split(":"); if (p.length < 2) return ""
    var h = Number(p[0]), ap = h >= 12 ? "PM" : "AM"
    return ((h % 12) || 12) + ":" + p[1] + " " + ap
  }
  function shiftTime(hm, mins) {
    var p = String(hm || "0:00").split(":"), t = (Number(p[0]) * 60 + Number(p[1]) + mins + 1440) % 1440
    return Math.floor(t / 60) + ":" + ("0" + (t % 60)).slice(-2)
  }
  readonly property string nightSubtitle: {
    var sched = nl.mode && nl.mode !== "manual" && nl.from
    if (nightOn) return sched ? "On until " + hm12(nl.to) : "On"
    return sched ? "Off · on at " + hm12(nl.from) : "Off"
  }
  property string dnd: ""

  // ================================================================ Tailscale / VPN
  property bool tsInstalled: false
  property var ts: ({})
  property bool tsBusy: false
  readonly property bool tsRunning: ts.BackendState === "Running"
  readonly property var tsExitNodes: {
    var p = ts.Peer || {}, list = []
    for (var k in p) if (p[k].ExitNodeOption) list.push({ ip: (p[k].TailscaleIPs || [""])[0], host: String(p[k].HostName || ""), online: !!p[k].Online, active: !!p[k].ExitNode })
    list.sort(function(a, b) { return a.host.localeCompare(b.host) })
    return list
  }
  readonly property var tsActiveExit: tsExitNodes.filter(function(e) { return e.active })[0] || null
  property var vpns: []

  // ================================================================ Hyprland
  property string defaultLayout: ""
  property string wsLayout: ""

  // ================================================================ Recording / reminders / sudo
  property bool recording: false
  property bool recDesktopAudio: true
  property bool recMic: false
  property bool recWebcam: false
  property var reminders: []
  property bool sudoFree: false
  property bool sudoBusy: false

  function startRecording(fullscreen) {
    var argv = ["omarchy-capture-screenrecording"]
    if (fullscreen) argv.push("--fullscreen")
    if (recDesktopAudio) argv.push("--with-desktop-audio")
    if (recMic) argv.push("--with-microphone-audio")
    if (recWebcam) argv.push("--with-webcam")
    // Closes the panel first: the region picker and the recording need the screen.
    qc.launch(argv, 250)
  }
  function stopRecording() {
    recording = false
    qc.runner.run(["omarchy-capture-screenrecording", "--stop-recording"], function() { q.refreshSlow() })
  }
  readonly property string reminderTool: Qt.resolvedUrl("../tools/reminder.py").toString().replace(/^file:\/\//, "").replace(/\?.*$/, "")
  function addReminder(minutes, message) {
    var m = Math.round(Number(minutes))
    if (!isFinite(m) || m < 1 || m > 10080) { qc.toast("Minutes must be 1–10080"); return }
    var msg = String(message || "").replace(/[\x00-\x1f]/g, " ").trim().slice(0, 200)
    var done = function(code) {
      q.qc.toast(code === 0 ? "Reminder set for " + m + " min" : "Could not set reminder")
      q.refreshSlow()
    }
    // Without text, Omarchy's own command. With text, our helper: the same
    // kind of reminder (Omarchy lists and clears it), but the text goes on
    // stdin and into a private file, never on a command line.
    if (msg === "") qc.runner.run(["omarchy-reminder", String(m)], done)
    else qc.runner.runWithInput(["python3", "-I", reminderTool, "set", String(m)], msg, done)
  }
  function cancelReminder(timer) {
    if (!/^omarchy-reminder-[A-Za-z0-9_.-]+\.timer$/.test(timer)) return
    qc.runner.run(["systemctl", "--user", "stop", timer], function() { q.refreshSlow() })
  }
  function disableSudo() {
    sudoBusy = true
    // An active grant can be revoked without a password.
    qc.runner.run(["omarchy-sudo-passwordless", "--disable"], function(code) {
      q.sudoBusy = false
      q.qc.toast(code === 0 ? "Passwordless sudo disabled" : "Could not disable passwordless sudo")
      q.refreshSlow()
    })
  }
  function enableSudo(duration) {
    // Enabling stays in Omarchy's own flow: it shows the security warning and
    // asks for your password in a terminal.
    qc.launchTerminal("omarchy-sudo-passwordless " + duration)
  }

  // ================================================================ Printers / scanners
  property var printers: []      // [{name, state, isDefault}]
  property var jobs: []          // [{id, user, size, when}]
  property var scanners: []      // [{device, label}]
  property bool scanning: false
  property bool scannedOnce: false

  // ================================================================ refresh
  function refreshSlow() {
    qc.runner.run(["hyprctl", "monitors", "all", "-j"], function(code, out) { try { q.displays = JSON.parse(out) } catch (e) {} })
    if (!laptopName) qc.runner.run(["omarchy-hyprland-monitor-laptop"], function(code, out) { q.laptopName = String(out).trim() })
    qc.runner.run(["brightnessctl", "-m", "-c", "backlight"], function(code, out) {
      var f = String(out).trim().split(",")
      q.brightness = code === 0 && f.length >= 5 && Number(f[4]) > 0 ? Number(f[2]) / Number(f[4]) : -1
    })
    qc.runner.run(["omarchy-powerprofiles-list", "--active-state"], function(code, out) {
      var list = [], active = ""
      String(out).split("\n").forEach(function(l) { var f = l.split("\t"); if (!f[0]) return; list.push(f[0]); if (f[1] === "1") active = f[0] })
      q.profiles = list; q.profile = active
    })
    refreshCharge()
    refreshKbd()
    qc.runner.run(["omarchy-capture-screenrecording", "--status"], function(code) { q.recording = code === 0 })
    qc.runner.run(["omarchy-reminder", "show", "-j"], function(code, out) {
      try { q.reminders = (JSON.parse(out).reminders || []).slice(0, 20) } catch (e) { q.reminders = [] }
    })
    qc.runner.run(["bash", "-c", "omarchy-sudo-passwordless --active"], function(code) { q.sudoFree = code === 0 })
    qc.runner.run(["omarchy-toggle-idle", "status"], function(code, out) {
      try { q.stayAwake = JSON.parse(out).enabled === true } catch (e) {}
    })
    qc.runner.run(["omarchy-toggle-nightlight", "--status"], function(code, out) {
      try { q.nightOn = JSON.parse(out).enabled === true } catch (e) {}
    })
    refreshNight()
    qc.runner.run(["omarchy-shell", "notifications", "isDnd"], function(code, out) {
      var s = String(out).trim(); q.dnd = code === 0 && (s === "on" || s === "off") ? s : ""
    })
    qc.runner.run(["tailscale", "status", "--json"], function(code, out) {
      if (code === 127) { q.tsInstalled = false; return }
      q.tsInstalled = true
      try { q.ts = JSON.parse(out) } catch (e) {}
    })
    qc.runner.run(["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"], function(code, out) {
      var list = []
      String(out).split("\n").forEach(function(l) {
        var f = l.split(":"); if (f.length < 3) return
        var type = f[f.length - 2]
        if (type === "vpn" || type === "wireguard") list.push({ name: f.slice(0, f.length - 2).join(":").replace(/\\/g, ""), active: f[f.length - 1] === "yes" })
      })
      q.vpns = list
    })
    qc.runner.run(["hyprctl", "-j", "getoption", "general:layout"], function(code, out) {
      try { q.defaultLayout = JSON.parse(out).str || "" } catch (e) {}
    })
    qc.runner.run(["omarchy-hyprland-workspace-layout-current"], function(code, out) { q.wsLayout = String(out).trim() })
    // Installed printers only (lpstat -v), like the Printers & Scanners page.
    // lpstat -e would also list every queue CUPS sees on the network,
    // including ones shared for printers that no longer exist.
    qc.runner.run(["sh", "-c", "lpstat -v 2>/dev/null | sed -n 's/^device for \\([^:]*\\):.*/\\1/p'"], function(code, names) {
      q.qc.runner.run(["lpstat", "-d", "-p"], function(c2, out) {
        var def = (/system default destination:\s*(\S+)/.exec(out) || [])[1] || ""
        var states = {}
        String(out).split("\n").forEach(function(l) {
          var m = /^printer (\S+) (?:is )?(\w+)/.exec(l)
          if (m) states[m[1]] = m[2]
        })
        q.printers = String(names).split("\n").filter(function(s) { return /^[\w.@-]+$/.test(s) }).map(function(n) {
          return { name: n, state: states[n] || "", isDefault: n === def }
        })
      })
    })
    qc.runner.run(["lpstat", "-o"], function(code, out) {
      q.jobs = String(out).split("\n").map(function(l) {
        var f = l.trim().split(/\s+/)
        return f.length >= 2 && /^[\w.@-]+-\d+$/.test(f[0]) ? { id: f[0], user: f[1], size: f[2] || "" } : null
      }).filter(function(x) { return x !== null })
    })
  }
  function scanForScanners() {
    if (scanning) return
    scanning = true
    // Listing scanners probes the network and can take ~10 s.
    qc.runner.run(["timeout", "25", "scanimage", "-f", "%d|%v %m%n", "-L"], function(code, out) {
      q.scanners = String(out).split("\n").map(function(l) {
        var i = l.indexOf("|")
        var f = i > 0 ? [l.slice(0, i), l.slice(i + 1)] : []
        return f.length === 2 && /^[a-z0-9_]+:\S+$/.test(f[0]) && f[0].indexOf("v4l:") !== 0 ? { device: f[0], label: f[1].trim() } : null
      }).filter(function(x) { return x !== null })
      q.scanning = false
      q.scannedOnce = true
    })
  }
  onExpandedChanged: {
    if (expanded === "scanners" && !scannedOnce) scanForScanners()
    Qt.callLater(function() { q.slideIn(q.currentView()) })
  }
  Timer { interval: 4000; running: true; repeat: true; triggeredOnStart: true; onTriggered: q.refreshSlow() }

  // ================================================================ pills
  readonly property var pills: {
    var list = []
    list.push({ id: "wifi", icon: Networking.wifiEnabled ? (wifiConnected ? Icons.wifiStrength(wifiConnected.signal) : Icons.wifi) : Icons.wifiOff,
                title: "Wi-Fi", subtitle: !Networking.wifiEnabled ? "Off" : wifiConnected ? wifiConnected.ssid : "Not connected",
                active: Networking.wifiEnabled, hasMenu: !!wifiDevice })
    if (wiredDevice)
      list.push({ id: "wired", icon: Icons.ethernet, title: "Wired", subtitle: wiredDevice.connected ? "Connected" : "Disconnected",
                  active: wiredDevice.connected, hasMenu: false })
    list.push({ id: "bluetooth", icon: btOn ? (btConnected.length ? Icons.bluetoothConnected : Icons.bluetooth) : Icons.bluetoothOff,
                title: "Bluetooth", subtitle: !btAdapter ? "Unavailable" : !btOn ? "Off" : btConnected.length === 1 ? btConnected[0].name
                  : btConnected.length > 1 ? btConnected.length + " devices" : "On", active: btOn, hasMenu: !!btAdapter })
    if (tsInstalled)
      list.push({ id: "tailscale", icon: Icons.vpn, title: "Tailscale",
                  subtitle: tsRunning ? (tsActiveExit ? "via " + tsActiveExit.host : ((ts.CurrentTailnet || {}).MagicDNSSuffix || "Connected").replace(/\.ts\.net$/, "")) : (ts.BackendState === "NeedsLogin" ? "Signed out" : "Off"),
                  active: tsRunning, hasMenu: true })
    if (vpns.length > 0) {
      var on = vpns.filter(function(v) { return v.active })
      list.push({ id: "vpn", icon: Icons.shield, title: "VPN", short: on.length ? on[0].name : "VPN", subtitle: on.length ? on[0].name : "Off", active: on.length > 0, hasMenu: true })
    }
    if (profiles.length > 0)
      list.push({ id: "power", icon: profile === "power-saver" ? String.fromCodePoint(0xF032A) : profile === "performance" ? String.fromCodePoint(0xF04C5) : Icons.bolt,
                  title: "Power Mode", subtitle: profile === "power-saver" ? "Power Saver" : profile === "performance" ? "Performance" : "Balanced",
                  active: profile !== "balanced" && profile !== "", hasMenu: true })
    list.push({ id: "sound", icon: volumeIcon(), title: "Sound",
                subtitle: volumeMuted ? "Muted" : (nodeLabel(volumeSink) || "No output"), active: !volumeMuted && !!volumeSink, hasMenu: true })
    var mirroring = displays.some(function(m) { return m.mirrorOf && m.mirrorOf !== "none" })
    list.push({ id: "display", icon: Icons.monitor, title: "Displays",
                subtitle: displaysOn.length <= 1 ? (displaysOn.length && displaysOn[0].name === laptopName ? "Built-in only" : "1 display")
                  : mirroring ? displaysOn.length + " displays · mirroring" : displaysOn.length + " displays",
                active: displaysOn.length > 1, hasMenu: true, menuOnly: true })
    list.push({ id: "night", icon: Icons.nightlight, title: "Night Light", subtitle: nightSubtitle, active: nightOn, hasMenu: true })
    var dndOn = notifActive ? notif.dnd : dnd === "on"
    list.push({ id: "dnd", icon: dndOn ? Icons.bellOff : Icons.bell, title: "Do Not Disturb",
                subtitle: !notifActive && dnd === "" ? "Unavailable" : dndOn ? "On" : "Off", active: dndOn, hasMenu: false })
    list.push({ id: "awake", icon: String.fromCodePoint(0xF0176), title: "Stay Awake", short: "Awake", subtitle: stayAwake ? "Screen stays on" : "Off", active: stayAwake, hasMenu: false })
    list.push({ id: "airplane", icon: String.fromCodePoint(0xF001D), title: "Airplane Mode", short: "Airplane", subtitle: airplane ? "On" : "Off", active: airplane, hasMenu: false })
    list.push({ id: "record", icon: recording ? String.fromCodePoint(0xF044A) : String.fromCodePoint(0xF0A1C), title: "Screen Record", short: "Record",
                subtitle: recording ? "Recording — click to stop" : "Off", active: recording, hasMenu: true })
    list.push({ id: "reminders", icon: String.fromCodePoint(0xF0020), title: "Reminders", short: "Reminders",
                subtitle: reminders.length ? reminders.length + " · next " + (reminders.slice().sort(function(a, b) { return a.remainingSeconds - b.remainingSeconds })[0].atTime || "") : "None set",
                active: reminders.length > 0, hasMenu: true, menuOnly: true })
    list.push({ id: "sudo", icon: String.fromCodePoint(0xF0FC5), title: "Passwordless Sudo", short: "Sudo",
                subtitle: sudoFree ? "On — sudo asks no password" : "Off", active: sudoFree, hasMenu: true })
    if (chargeLimit > 0)
      list.push({ id: "charge", icon: chargeLimit >= 100 ? Icons.batteryCharging : String.fromCodePoint(0xF0081), title: "Full Charge",
                  short: chargeLimit >= 100 ? "Charge 100%" : "Limit " + chargeLimit + "%", subtitle: "", active: chargeLimit >= 100, hasMenu: false })
    list.push({ id: "layout", icon: Icons.windows, title: "Window Layout", subtitle: wsLayout ? wsLayout.charAt(0).toUpperCase() + wsLayout.slice(1) : "—", active: false, hasMenu: true })
    list.push({ id: "printers", icon: Icons.printer, title: "Printers",
                subtitle: jobs.length ? jobs.length + (jobs.length === 1 ? " job" : " jobs") : (printers.filter(function(p) { return p.isDefault })[0] || {}).name || (printers.length ? printers.length + (printers.length === 1 ? " printer" : " printers") : "None"),
                active: jobs.length > 0, hasMenu: true, menuOnly: true })
    list.push({ id: "scanners", icon: String.fromCodePoint(0xF06AB), title: "Scanners",
                subtitle: scanning ? "Searching…" : scannedOnce ? (scanners.length ? scanners.length + " found" : "None found") : "Scan a document",
                active: false, hasMenu: true, menuOnly: true })
    return list
  }
  readonly property bool airplane: !Networking.wifiEnabled && !btOn

  function pillTip(p) {
    if (!p || !p.id) return ""
    switch (p.id) {
    case "power": return "Switch between Balanced and Power Saver"
    case "sound": return p.active ? "Mute sound" : "Unmute sound"
    case "display": return "Displays, arrangement and mirroring"
    case "record": return p.active ? "Stop the recording" : "Record a region of the screen"
    case "reminders": return "Set, see and cancel reminders"
    case "layout": return "Cycle this workspace: dwindle → scrolling → floating"
    case "printers": return "Printers and print jobs"
    case "scanners": return "Find scanners and scan a document"
    case "awake": return p.active ? "Allow the screen to lock and sleep again" : "Keep the screen on: no dimming, lock or screensaver"
    case "airplane": return p.active ? "Turn Wi-Fi and Bluetooth back on" : "Turn off Wi-Fi and Bluetooth"
    case "charge": return p.active ? "Charging to 100% — click to limit charging to " + savedChargeLimit + "% again"
      : "Charging stops at " + chargeLimit + "% to protect the battery — click to charge to 100%"
    case "vpn": return p.active ? "Disconnect " + p.subtitle + " (right-click: all VPNs)" : "Connect a VPN (right-click: choose)"
    case "sudo": return p.active ? "Require a password for sudo again" : "Let sudo run without a password for a while"
    case "dnd": return p.active ? "Show notification pop-ups again" : "Silence notification pop-ups"
    default: return (p.active ? "Turn off " : "Turn on ") + p.title
    }
  }
  function menuTipFor(id) {
    return ({ wifi: "Networks", bluetooth: "Devices", tailscale: "Exit node", vpn: "VPN connections",
              power: "Power modes", layout: "Window layout options", record: "Recording options",
              sudo: "How long" })[id] || ""
  }

  // Big tiles: the everyday toggles. Small round chips: the rest that are
  // quick toggles. Wired, printers, scanners and window layout live on their
  // settings pages (All settings).
  readonly property var mainIds: ["wifi", "bluetooth", "sound", "tailscale", "power", "display", "night", "dnd"]
  readonly property var chipIds: ["awake", "airplane", "record", "reminders", "vpn", "sudo", "charge"]
  readonly property var mainPills: pills.filter(function(p) { return q.mainIds.indexOf(p.id) >= 0 })
  readonly property var chips: pills.filter(function(p) { return q.chipIds.indexOf(p.id) >= 0 })
  readonly property var pillRows: {
    var rows = []
    for (var i = 0; i < mainPills.length; i += 2) rows.push(mainPills.slice(i, i + 2))
    return rows
  }
  readonly property int chipCount: chips.length
  readonly property var chipIdList: chips.map(function(c) { return c.id })

  function pillToggle(id) {
    switch (id) {
    case "sound": if (volumeSink && volumeSink.audio) volumeSink.audio.muted = !volumeSink.audio.muted; break
    case "wifi": Networking.wifiEnabled = !Networking.wifiEnabled; break
    case "wired": qc.runner.run(["nmcli", "device", wiredDevice.connected ? "disconnect" : "connect", String(wiredDevice.name)], null); break
    case "bluetooth": qc.runner.run(["omarchy-bluetooth-power", btOn ? "off" : "on"], null); break
    case "tailscale":
      if (!tsRunning && ts.BackendState === "NeedsLogin") { qc.close(); qc.summonPlugin("omarchy.tailscale"); break }
      tsBusy = true
      qc.runner.run(["tailscale", tsRunning ? "down" : "up"], function(code) {
        q.tsBusy = false
        if (code !== 0) q.qc.notify("Tailscale", "Needs operator rights: sudo tailscale set --operator=$USER")
        q.refreshSlow()
      })
      break
    case "vpn": {
      var on = vpns.filter(function(v) { return v.active })
      var target = on.length ? on[0] : vpns[0]
      qc.runner.run(["nmcli", "connection", target.active ? "down" : "up", "id", target.name], function() { q.refreshSlow() })
      break
    }
    case "power": setProfile(profile === "balanced" ? "power-saver" : "balanced"); break
    case "night":
      nightOn = !nightOn
      nightApply(nightOn)
      break
    case "dnd":
      if (notifActive) notif.setDnd(!notif.dnd)
      else qc.runner.run(["omarchy-toggle-notification-silencing"], function() { q.refreshSlow() })
      break
    case "awake":
      stayAwake = !stayAwake
      qc.runner.run(["omarchy-toggle-idle", stayAwake ? "stay-awake" : "allow-idle"], function() { q.refreshSlow() })
      break
    case "airplane":
      if (airplane) { Networking.wifiEnabled = true; qc.runner.run(["omarchy-bluetooth-power", "on"], null) }
      else { Networking.wifiEnabled = false; qc.runner.run(["omarchy-bluetooth-power", "off"], null) }
      break
    case "record": if (recording) stopRecording(); else startRecording(false); break
    case "sudo": if (sudoFree) disableSudo(); else toggleMenu("sudo"); break
    case "layout": qc.runner.run(["omarchy-hyprland-workspace-layout-toggle"], function() { q.refreshSlow() }); break
    case "charge": setChargeLimit(chargeLimit >= 100 ? savedChargeLimit : 100); break
    }
  }

  // ================================================================ charge limit
  // The battery's charge stop (charge_control_end_threshold). Read and set
  // through asusctl when it's there (no password), otherwise straight in
  // sysfs, writing through pkexec. -1: this machine has no such setting.
  property int chargeLimit: -1
  property int savedChargeLimit: 80
  property string chargeFile: ""
  property bool hasAsusctl: false
  readonly property string chargeStateFile: Quickshell.env("HOME") + "/.local/state/omarchy/control-center/charge-limit"
  function refreshCharge() {
    qc.runner.run(["sh", "-c", "command -v asusctl >/dev/null && echo asus; ls /sys/class/power_supply/*/charge_control_end_threshold 2>/dev/null | head -1; cat \"$1\" 2>/dev/null", "sh", chargeStateFile], function(code, out) {
      var lines = String(out).split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
      q.hasAsusctl = lines.indexOf("asus") >= 0
      var file = lines.filter(function(l) { return l.indexOf("/sys/") === 0 })[0] || ""
      q.chargeFile = file
      var saved = Number(lines.filter(function(l) { return /^\d+$/.test(l) })[0])
      if (saved >= 20 && saved < 100) q.savedChargeLimit = saved
      if (!file || !q.hasBattery) { q.chargeLimit = -1; return }
      q.qc.runner.run(["cat", file], function(c2, v) { var n = parseInt(String(v), 10); q.chargeLimit = c2 === 0 && n > 0 ? n : -1 })
    })
  }
  function setChargeLimit(n) {
    if (!chargeFile) return
    var old = chargeLimit
    if (old > 0 && old < 100)
      qc.runner.run(["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && echo \"$2\" > \"$1\"", "sh", chargeStateFile, String(old)], null)
    chargeLimit = n
    var cmd = hasAsusctl ? ["asusctl", "battery", "limit", String(n)]
      : ["pkexec", "sh", "-c", "echo \"$1\" > \"$2\"", "sh", String(n), chargeFile]
    qc.runner.run(cmd, function(code) { if (code !== 0) q.qc.notify("Battery", "Couldn't change the charge limit"); q.refreshCharge() })
  }

  // ================================================================ keyboard backlight
  // Any *kbd_backlight* LED; brightnessctl sets it through logind, no root.
  property string kbdDevice: ""
  property int kbdLevel: 0
  property int kbdMax: 0
  function refreshKbd() {
    qc.runner.run(["brightnessctl", "-m", "-c", "leds", "-d", "*kbd_backlight*"], function(code, out) {
      var f = String(out).trim().split("\n")[0].split(",")
      if (code !== 0 || f.length < 5 || Number(f[4]) <= 0) { q.kbdDevice = ""; return }
      q.kbdDevice = f[0]; q.kbdLevel = Number(f[2]); q.kbdMax = Number(f[4])
    })
  }
  function setKbd(frac) {
    if (!kbdDevice) return
    var n = Math.max(0, Math.min(kbdMax, Math.round(frac * kbdMax)))
    if (n === kbdLevel) return
    kbdLevel = n
    qc.runner.run(["brightnessctl", "-q", "-d", kbdDevice, "set", String(n)], null)
  }
  function setProfile(p) {
    profile = p
    qc.runner.run(["omarchy-powerprofiles-set", UPower.onBattery ? "battery" : "ac", p], function() { q.refreshSlow() })
  }

  // ================================================================ layout
  Column {
    id: col
    width: parent.width
    spacing: Style.space(14)
    visible: q.page === "" && q.expanded === ""

    // ---------------------------------------------------- header
    Item {
      width: parent.width
      height: Style.space(38)

      Rectangle {
        visible: q.hasBattery
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(38)
        width: batRow.implicitWidth + Style.space(28)
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        color: Qt.rgba(q.fg.r, q.fg.g, q.fg.b, batMouse.containsMouse ? 0.16 : 0.08)
        GlassShadow { depth: 1 }
        Glass {}
        Row {
          id: batRow
          anchors.centerIn: parent
          spacing: Style.space(6)
          Text {
            textFormat: Text.PlainText
            text: q.battery && q.battery.state === UPowerDeviceState.Charging ? Icons.batteryCharging : q.qc.batteryGlyph
            color: q.fg; font.family: Style.font.family; font.pixelSize: Style.font.icon
          }
          Text {
            textFormat: Text.PlainText
            text: q.hasBattery ? Math.round(q.battery.percentage * 100) + "%" : ""
            color: q.fg; font.family: Style.font.menuFamily; font.pixelSize: Style.font.body
          }
        }
        id: batChip
        property bool ccFocusable: visible
        property bool hasCursor: false
        function ccActivate() { q.openPage("power") }
        border.width: hasCursor ? 2 : 0
        border.color: Color.accent
        MouseArea { id: batMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: q.openPage("power") }
        PanelToolTip {
          visible: batMouse.containsMouse || batChip.hasCursor
          text: q.hasBattery ? (UPower.onBattery ? "On battery" : "Plugged in")
            + (q.battery.timeToEmpty > 0 && UPower.onBattery ? " · " + Math.round(q.battery.timeToEmpty / 60) + " min left" : "")
            + (q.battery.timeToFull > 0 && !UPower.onBattery ? " · full in " + Math.round(q.battery.timeToFull / 60) + " min" : "")
            + " — battery & power settings" : ""
        }
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)
        QsRoundButton { icon: String.fromCodePoint(0xF0100); tip: "Take a screenshot"; onClicked: q.qc.launch(["omarchy-capture-screenshot"], 350) }
        QsRoundButton { icon: Icons.cog; tip: "All settings"; onClicked: q.openPage("index") }
        QsRoundButton { icon: Icons.lock; tip: "Lock screen"; onClicked: q.qc.launch(["omarchy-system-lock"], 150) }
        QsRoundButton { icon: Icons.power; tip: "Suspend, restart, power off or log out"; active: q.expanded === "session"; onClicked: q.toggleMenu("session") }
      }
    }

    Component {
      id: sessionMenu
      QsMenu {
        icon: Icons.power
        title: "Power Off"
        QsMenuItem { icon: Icons.sleep; text: "Suspend"; onClicked: q.qc.launch(["systemctl", "suspend"], 200) }
        QsMenuItem { icon: Icons.restart; text: "Restart…"; onClicked: q.qc.launch(["omarchy-system", "reboot"], 150) }
        QsMenuItem { icon: Icons.power; text: "Power Off…"; onClicked: q.qc.launch(["omarchy-system", "shutdown"], 150) }
        QsMenuItem { icon: Icons.logout; text: "Log Out…"; separatorAbove: true; onClicked: q.qc.launch(["omarchy-system", "logout"], 150) }
      }
    }

    // ---------------------------------------------------- now playing
    NowPlaying { id: nowPlaying; show: q.qc.showNowPlaying; store: q.qc }

    // ---------------------------------------------------- sliders
    Column {
      width: parent.width
      spacing: Style.space(6)

      QsSlider {
        icon: q.volumeIcon()
        value: q.volume
        to: 1
        muted: q.volumeMuted
        hasMenu: q.sinks.length > 0
        expanded: q.expanded === "outputs"
        iconTip: q.volumeMuted ? "Unmute" : "Mute"
        menuTip: "Choose output device"
        valueTip: "Volume " + Math.round(q.volume * 100) + "% · " + q.nodeLabel(q.defaultSink)
        onIconClicked: if (q.volumeSink && q.volumeSink.audio) q.volumeSink.audio.muted = !q.volumeSink.audio.muted
        onMoved: function(v) { if (q.volumeSink && q.volumeSink.audio) { q.volumeSink.audio.volume = v; if (v > 0) q.volumeSink.audio.muted = false } }
        onCommitted: function(v) { if (q.volumeSink && q.volumeSink.audio) q.volumeSink.audio.volume = v }
        onMenuRequested: q.toggleMenu("outputs")
      }
      Component {
        id: outputsMenu
        QsMenu {
                  icon: Icons.speaker
          title: "Sound Output"
          Repeater {
            model: q.expanded === "outputs" ? q.sinks.map(function(n) { return { id: n.id, name: String(n.name), label: q.nodeLabel(n), icon: q.nodeIcon(n, false) } }) : []
            delegate: QsMenuItem {
              required property var modelData
              icon: modelData.icon
              text: modelData.label
              checked: (q.defaultSink && q.defaultSink.id === modelData.id) || q.volumeSinkName === modelData.name
              onClicked: q.qc.setAudioOutput(modelData.id, modelData.name)
            }
          }
          QsMenuItem { text: "Sound Settings"; separatorAbove: true; onClicked: q.openPage("sound") }
        }
      }

      Column {
        width: parent.width
        visible: !!q.alsoPlayingSink
        spacing: Style.space(2)
        Text {
          x: Style.space(48)
          width: parent.width - x
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: "Also playing on " + q.nodeLabel(q.alsoPlayingSink)
          color: Qt.rgba(q.fg.r, q.fg.g, q.fg.b, 0.7)
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }
        QsSlider {
          icon: q.alsoMuted || q.alsoVolume <= 0.001 ? Icons.volumeOff : Icons.speaker
          value: q.alsoVolume
          to: 1
          muted: q.alsoMuted
          ccFocusable: visible && parent.visible
          iconTip: q.alsoMuted ? "Unmute" : "Mute"
          valueTip: q.nodeLabel(q.alsoPlayingSink) + " " + Math.round(q.alsoVolume * 100) + "%"
          onIconClicked: if (q.alsoPlayingSink && q.alsoPlayingSink.audio) q.alsoPlayingSink.audio.muted = !q.alsoPlayingSink.audio.muted
          onMoved: function(v) { if (q.alsoPlayingSink && q.alsoPlayingSink.audio) { q.alsoPlayingSink.audio.volume = v; if (v > 0) q.alsoPlayingSink.audio.muted = false } }
          onCommitted: function(v) { if (q.alsoPlayingSink && q.alsoPlayingSink.audio) q.alsoPlayingSink.audio.volume = v }
        }
      }

      QsSlider {
        visible: q.defaultSource !== null && q.sources.length > 0
        icon: q.defaultSource && q.defaultSource.audio && q.defaultSource.audio.muted ? Icons.microphoneOff : Icons.microphone
        value: q.defaultSource && q.defaultSource.audio ? q.defaultSource.audio.volume : 0
        muted: !!(q.defaultSource && q.defaultSource.audio && q.defaultSource.audio.muted)
        hasMenu: q.sources.length > 0
        expanded: q.expanded === "inputs"
        iconTip: muted ? "Unmute microphone" : "Mute microphone"
        menuTip: "Choose input device"
        valueTip: "Microphone " + Math.round(value * 100) + "% · " + q.nodeLabel(q.defaultSource)
        onIconClicked: q.qc.runner.run(["omarchy-audio-input-mute"], null)
        onMoved: function(v) { if (q.defaultSource && q.defaultSource.audio) q.defaultSource.audio.volume = v }
        onCommitted: function(v) { if (q.defaultSource && q.defaultSource.audio) q.defaultSource.audio.volume = v }
        onMenuRequested: q.toggleMenu("inputs")
      }
      Component {
        id: inputsMenu
        QsMenu {
                  icon: Icons.microphone
          title: "Sound Input"
          Repeater {
            model: q.expanded === "inputs" ? q.sources.map(function(n) { return { id: n.id, name: String(n.name), label: q.nodeLabel(n), icon: q.nodeIcon(n, true) } }) : []
            delegate: QsMenuItem {
              required property var modelData
              icon: modelData.icon
              text: modelData.label
              checked: q.defaultSource && q.defaultSource.id === modelData.id
              onClicked: q.qc.runner.run(["omarchy-audio-input-set-default", String(modelData.id), modelData.name], null)
            }
          }
        }
      }

      QsSlider {
        visible: q.brightness >= 0
        icon: Icons.brightness
        value: q.brightness
        ccFocusable: visible
        valueTip: "Brightness " + Math.round(q.brightness * 100) + "%"
        function ccActivate() {}
        onMoved: function(v) { q.pendingBrightness = v; brightnessApply.restart() }
        onCommitted: function(v) { q.brightness = v; q.pendingBrightness = v; brightnessApply.restart() }
      }

      // Keyboard backlight: steps (often 0–3), so the slider snaps.
      QsSlider {
        visible: q.kbdDevice !== "" && q.kbdMax > 0
        icon: q.kbdLevel > 0 ? String.fromCodePoint(0xF0313) : String.fromCodePoint(0xF12AA)
        value: q.kbdMax > 0 ? q.kbdLevel / q.kbdMax : 0
        muted: q.kbdLevel === 0
        iconTip: q.kbdLevel > 0 ? "Turn the keyboard light off" : "Turn the keyboard light on"
        valueTip: "Keyboard light " + q.kbdLevel + " of " + q.kbdMax
        function ccAdjust(dir) { q.setKbd((q.kbdLevel + dir) / q.kbdMax); return true }
        onIconClicked: q.setKbd(q.kbdLevel > 0 ? 0 : 1)
        onMoved: function(v) { q.setKbd(v) }
        onCommitted: function(v) { q.setKbd(v) }
      }
    }

    // ---------------------------------------------------- pill grid
    Column {
      width: parent.width
      spacing: Style.space(10)

      Repeater {
        // A count, not the rows themselves: pill state changes every few
        // seconds and must not rebuild the delegates (and lose the cursor).
        model: q.pillRows.length
        delegate: Column {
          id: pairRow
          required property int index
          readonly property var modelData: q.pillRows[index] || []
          width: parent.width
          spacing: Style.space(10)
          readonly property var ids: modelData.map(function(p) { return p.id })

          Row {
            width: parent.width
            spacing: Style.space(10)
            Repeater {
              model: pairRow.modelData.length
              delegate: QsPill {
                required property int index
                readonly property var modelData: pairRow.modelData[index] || ({})
                width: (pairRow.width - Style.space(10)) / 2
                tip: q.pillTip(modelData)
                menuTip: q.menuTipFor(modelData.id)
                icon: modelData.icon
                title: modelData.title
                subtitle: modelData.subtitle
                active: modelData.active
                hasMenu: modelData.hasMenu
                menuOnly: !!modelData.menuOnly
                busy: modelData.id === "tailscale" && q.tsBusy
                expanded: q.expanded === modelData.id
                onToggled: q.pillToggle(modelData.id)
                onMenuRequested: q.toggleMenu(modelData.id)
              }
            }
          }

        }
      }
    }

    // ---------------------------------------------------- small toggles
    Column {
      width: parent.width
      spacing: Style.space(10)
      visible: q.chipCount > 0
      readonly property int perRow: Math.min(6, Math.max(4, q.chipCount))
      Grid {
        id: chipGrid
        width: parent.width
        columns: parent.perRow
        readonly property real cellW: Math.floor(width / columns)
        Repeater {
          // A count, not the chips themselves (see the pill grid).
          model: q.chipCount
          delegate: QsChip {
            required property int index
            readonly property var modelData: q.chips[index] || ({})
            width: chipGrid.cellW
            icon: modelData.icon || ""
            label: modelData.short || modelData.title || ""
            active: !!modelData.active
            hasMenu: !!modelData.hasMenu
            menuOnly: !!modelData.menuOnly
            expanded: q.expanded === modelData.id
            tip: q.pillTip(modelData)
            onToggled: q.pillToggle(modelData.id)
            onMenuRequested: q.toggleMenu(modelData.id)
          }
        }
      }
    }

    // ---------------------------------------------------- today
    TodayEvents {
      svc: q.notif
      onOpenCalendar: function(dayMs) { q.qc.calendarDay = dayMs; q.openPage("calendar") }
    }

    // ---------------------------------------------------- notifications
    Column {
      width: parent.width
      spacing: Style.space(8)
      visible: !!q.notif

      Item {
        width: parent.width
        height: Style.space(30)
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: q.notifActive ? (q.notif.count ? "Notifications  ·  " + q.notif.count : "No Notifications") : "Notifications"
          color: q.fg
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
          font.underline: notifHeadMouse.containsMouse
          // The heading opens the full list too.
          MouseArea {
            id: notifHeadMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: q.openPage("notifications")
          }
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Button {
            visible: q.notifActive && q.notif.count > 0
            text: "Clear All"
            bordered: true
            foreground: q.fg
            fontSize: Style.font.bodySmall
            property bool ccFocusable: visible
            function ccActivate() { clicked() }
            onClicked: q.notif.clearAll()
          }
        }
      }

      QsMenuItem {
        visible: !q.notifActive
        icon: Icons.bell
        text: q.notif && q.notif.owner === "island" ? "Dynamic Island shows your notifications"
          : q.notif && q.notif.owner === "starting" ? "Taking over notifications…" : "Omarchy shows your notifications"
        detail: "Turn on the notification center to see, act on and reply to them here"
        trailing: "\uf054"
        onClicked: q.openPage("notifications")
      }

      Repeater {
        model: q.notifActive ? q.notif.rows.slice(0, q.notifShown) : []
        delegate: NotifCard {
          required property var modelData
          row: modelData
          svc: q.notif
          compact: true
          width: parent ? parent.width : 0
        }
      }
      QsMenuItem {
        visible: q.notifActive && q.notif.count > q.notifShown
        text: "Show All " + (q.notifActive ? q.notif.count : 0) + " Notifications"
        trailing: "\uf054"
        onClicked: q.openPage("notifications")
      }
    }
  }

  // ================================================================ menu view
  // A tile's, slider's or chip's menu takes over the panel (like macOS
  // Control Center) instead of growing it in place; back or Esc returns.
  readonly property var menuComponents: ({
    wifi: wifiMenu, bluetooth: btMenu, tailscale: tsMenu, vpn: vpnMenu, power: powerMenu,
    night: nightMenu, sound: soundMenu, display: displayMenu, layout: layoutMenu,
    printers: printerMenu, scanners: scannerMenu, record: recordMenu, reminders: reminderMenu,
    sudo: sudoMenu, session: sessionMenu, outputs: outputsMenu, inputs: inputsMenu
  })
  Column {
    id: menuView
    width: parent.width
    spacing: Style.space(10)
    visible: q.page === "" && q.expanded !== ""

    QsRoundButton {
      icon: "\uf053"
      tip: "Back (Esc)"
      onClicked: { q.navDir = -1; q.expanded = ""; q.resetCursor() }
    }
    Loader {
      width: parent.width
      active: menuView.visible
      sourceComponent: q.menuComponents[q.expanded] || null
    }
  }

  // ================================================================ notifications
  readonly property var notif: qc.notifService
  readonly property bool notifActive: !!notif && notif.active
  // Cards shown in the panel: two, or one while the music card takes room;
  // the rest are behind "Show All".
  readonly property int notifShown: qc.showNowPlaying ? 1 : 2

  // ================================================================ page view
  Column {
    id: pageView
    width: parent.width
    visible: q.page !== ""
    spacing: Style.space(8)

    Item {
      width: parent.width
      height: Style.space(38)
      QsRoundButton {
        id: backBtn
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        icon: "\uf053"
        tip: "Back (Esc)"
        onClicked: q.back()
      }
      Row {
        anchors.centerIn: parent
        spacing: Style.space(8)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: q.pageInfo.icon || ""
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.icon
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: q.pageInfo.title || ""
          color: q.fg
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
        }
      }
      QsRoundButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: q.page !== "index"
        icon: Icons.cog
        tip: "All settings"
        onClicked: q.openPage("index")
      }
    }

    Loader {
      width: parent.width
      active: q.page === "index"
      visible: active
      height: item ? item.implicitHeight : 0
      sourceComponent: indexPage
    }
    Loader {
      id: pageLoader
      width: parent.width
      visible: q.page !== "" && q.page !== "index"
      height: item && visible ? item.implicitHeight : 0
      Component.onCompleted: load()
      function load() {
        if (q.page === "" || q.page === "index") { if (q.page === "") setSource(""); return }
        var info = Pages.find(q.page)
        if (info) setSource(Qt.resolvedUrl("../pages/" + info.file) + "?v=" + q.qc.buildStamp, { cc: q.qc })
      }
      Connections { target: q; function onPageChanged() { pageLoader.load() } }
    }
  }

  Component {
    id: indexPage
    Column {
      width: parent ? parent.width : 0
      spacing: Style.space(10)
      TextField {
        id: search
        width: parent.width
        placeholderText: "Search settings"
        foreground: Color.menu.text
        property bool ccFocusable: visible
        property bool hasCursor: false
        function ccActivate() { forceActiveFocus() }
        Component.onCompleted: q.searchField = search
        Keys.onReturnPressed: {
          var hits = Pages.filter(text)
          if (hits.length) q.openPage(hits[0].id)
        }
        Keys.onDownPressed: function(e) { q.qc.focusKeys(); q.moveCursor(0, 1); e.accepted = true }
      }
      QsMenu {
        Repeater {
          model: Pages.filter(search.text)
          delegate: QsMenuItem {
            required property var modelData
            icon: modelData.icon
            text: modelData.title
            trailing: "\uf054"
            onClicked: q.openPage(modelData.id)
          }
        }
        QsMenuItem { visible: Pages.filter(search.text).length === 0; text: "No matching settings"; clickable: false; dim: true }
      }
    }
  }
  property var searchField: null

  // ================================================================ menus
  Component {
    id: wifiMenu
    QsMenu {
      icon: Icons.wifi
      title: "Wi-Fi"
      active: Networking.wifiEnabled
      QsMenuItem { visible: !Networking.wifiEnabled; text: "Wi-Fi is off"; clickable: false; dim: true }
      QsMenuItem { visible: Networking.wifiEnabled && q.wifiRows.length === 0; text: "Searching…"; clickable: false; dim: true }
      Repeater {
        model: Networking.wifiEnabled ? q.wifiRows.slice(0, 8) : []
        delegate: Column {
          id: wr
          required property var modelData
          width: parent ? parent.width : 0
          QsMenuItem {
            icon: Icons.wifiStrength(wr.modelData.signal)
            text: wr.modelData.ssid
            detail: wr.modelData.changing ? "Connecting…" : ""
            checked: wr.modelData.connected
            trailing: wr.modelData.secure && !wr.modelData.known ? Icons.lock : ""
            onClicked: {
              if (wr.modelData.connected) return
              if (wr.modelData.secure && !wr.modelData.known) { q.passwordFor = q.passwordFor === wr.modelData.ssid ? "" : wr.modelData.ssid; return }
              var o = q.wifiObject(wr.modelData.ssid); if (o) o.connect()
            }
          }
          Row {
            visible: q.passwordFor === wr.modelData.ssid
            height: visible ? implicitHeight + Style.space(8) : 0
            leftPadding: Style.space(40)
            spacing: Style.space(8)
            TextField {
              id: pw
              width: Style.space(200)
              password: true
              placeholderText: "Password"
              foreground: Color.menu.text
              onVisibleChanged: if (visible) forceActiveFocus()
              Keys.onReturnPressed: go.clicked()
            }
            Button {
              id: go
              text: "Connect"
              bordered: true
              foreground: Color.menu.text
              fontSize: Style.font.bodySmall
              onClicked: {
                if (pw.text === "") return
                var secret = pw.text, o = q.wifiObject(wr.modelData.ssid)
                if (o) o.connectWithPsk(secret)
                pw.text = ""; q.passwordFor = ""
              }
            }
          }
        }
      }
      QsMenuItem { text: "All Networks"; separatorAbove: true; onClicked: q.openPage("wifi") }
      QsMenuItem { text: "Devices on This Network"; onClicked: q.openPage("devices") }
    }
  }

  Component {
    id: btMenu
    QsMenu {
      icon: Icons.bluetooth
      title: "Bluetooth"
      active: q.btOn
      QsMenuItem { visible: !q.btOn; text: "Bluetooth is off"; clickable: false; dim: true }
      QsMenuItem { visible: q.btOn && q.btRows.length === 0; text: "No paired devices"; clickable: false; dim: true }
      Repeater {
        model: q.btOn ? q.btRows : []
        delegate: QsMenuItem {
          required property var modelData
          icon: Icons.bluetoothDevice(modelData.icon)
          text: modelData.name
          detail: q.btPending[modelData.address] ? (q.btPending[modelData.address] === "connect" ? "Connecting…" : "Disconnecting…")
            : modelData.busy ? "Working…" : ""
          trailing: modelData.battery >= 0 ? modelData.battery + "%" : ""
          checked: modelData.connected && modelData.battery < 0
          onClicked: q.btAct(modelData, modelData.connected ? "disconnect" : "connect")
        }
      }
      QsMenuItem { text: "Bluetooth Settings"; separatorAbove: true; onClicked: q.openPage("bluetooth") }
    }
  }

  Component {
    id: tsMenu
    QsMenu {
      icon: Icons.vpn
      title: "Exit Node"
      active: q.tsRunning
      QsMenuItem { visible: !q.tsRunning; text: "Tailscale is off"; clickable: false; dim: true }
      QsMenuItem {
        visible: q.tsRunning
        text: "None"
        detail: "Use your own internet connection"
        checked: !q.tsActiveExit
        onClicked: q.qc.runner.run(["tailscale", "set", "--exit-node="], function() { q.refreshSlow() })
      }
      Repeater {
        model: q.tsRunning ? q.tsExitNodes : []
        delegate: QsMenuItem {
          required property var modelData
          icon: Icons.web
          text: modelData.host
          detail: modelData.online ? modelData.ip : "offline"
          dim: !modelData.online
          checked: modelData.active
          onClicked: q.qc.runner.run(["tailscale", "set", "--exit-node=" + modelData.ip], function(code) {
            if (code !== 0) q.qc.notify("Tailscale", "Could not switch exit node")
            q.refreshSlow()
          })
        }
      }
      QsMenuItem { text: "Tailscale Settings"; separatorAbove: true; onClicked: q.openPage("tailscale") }
    }
  }

  Component {
    id: vpnMenu
    QsMenu {
      icon: Icons.shield
      title: "VPN"
      Repeater {
        model: q.vpns
        delegate: QsMenuItem {
          required property var modelData
          text: modelData.name
          checked: modelData.active
          onClicked: q.qc.runner.run(["nmcli", "connection", modelData.active ? "down" : "up", "id", modelData.name], function() { q.refreshSlow() })
        }
      }
      QsMenuItem { text: "Network Settings"; separatorAbove: true; onClicked: q.openPage("network") }
      QsMenuItem { text: "Devices on This Network"; onClicked: q.openPage("devices") }
    }
  }

  Component {
    id: soundMenu
    QsMenu {
      icon: Icons.speaker
      title: "Sound"
      Text {
        leftPadding: Style.space(10)
        topPadding: Style.space(2)
        text: "Output"
        color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }
      Repeater {
        model: q.sinks.map(function(n) { return { id: n.id, name: String(n.name), label: q.nodeLabel(n), icon: q.nodeIcon(n, false) } })
        delegate: QsMenuItem {
          required property var modelData
          icon: modelData.icon
          text: modelData.label
          checked: (q.defaultSink && q.defaultSink.id === modelData.id) || q.volumeSinkName === modelData.name
          onClicked: q.qc.setAudioOutput(modelData.id, modelData.name)
        }
      }
      QsMenuItem {
        icon: q.volumeMuted ? String.fromCodePoint(0xF075F) : Icons.volume
        text: q.volumeMuted ? "Unmute sound" : "Mute sound"
        onClicked: if (q.volumeSink && q.volumeSink.audio) q.volumeSink.audio.muted = !q.volumeSink.audio.muted
      }
      Text {
        leftPadding: Style.space(10)
        topPadding: Style.space(10)
        text: "Input"
        color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }
      Repeater {
        model: q.sources.map(function(n) { return { id: n.id, name: String(n.name), label: q.nodeLabel(n), icon: q.nodeIcon(n, true) } })
        delegate: QsMenuItem {
          required property var modelData
          icon: modelData.icon
          text: modelData.label
          checked: q.defaultSource && q.defaultSource.id === modelData.id
          onClicked: q.qc.runner.run(["omarchy-audio-input-set-default", String(modelData.id), modelData.name], null)
        }
      }
      QsMenuItem {
        readonly property bool micMuted: !!(q.defaultSource && q.defaultSource.audio && q.defaultSource.audio.muted)
        visible: !!q.defaultSource
        icon: micMuted ? Icons.microphoneOff : Icons.microphone
        text: micMuted ? "Unmute microphone" : "Mute microphone"
        onClicked: q.qc.runner.run(["omarchy-audio-input-mute"], null)
      }
      Text {
        leftPadding: Style.space(10)
        topPadding: Style.space(10)
        text: "Apps"
        color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }
      QsMenuItem { visible: q.streams.length === 0; text: "Nothing is playing"; clickable: false; dim: true }
      Repeater {
        model: q.streams
        delegate: QsSlider {
          required property var modelData
          width: parent ? parent.width : 0
          icon: modelData.audio && modelData.audio.muted ? String.fromCodePoint(0xF075F) : Icons.app
          value: modelData.audio ? modelData.audio.volume : 0
          to: 1.5
          muted: !!(modelData.audio && modelData.audio.muted)
          iconTip: muted ? "Unmute " + q.streamName(modelData) : "Mute " + q.streamName(modelData)
          valueTip: q.streamName(modelData) + " · " + Math.round(value * 100) + "%"
          onIconClicked: if (modelData.audio) modelData.audio.muted = !modelData.audio.muted
          onMoved: function(v) { if (modelData.audio) modelData.audio.volume = v }
          onCommitted: function(v) { if (modelData.audio) modelData.audio.volume = v }
        }
      }
      QsMenuItem { text: "Sound Settings"; separatorAbove: true; onClicked: q.openPage("sound") }
    }
  }

  Component {
    id: displayMenu
    QsMenu {
      icon: Icons.monitor
      title: "Displays"
      Repeater {
        model: q.displays.slice().sort(function(a, b) { return (a.disabled - b.disabled) || a.x - b.x || a.y - b.y }).map(function(m) {
          return { name: m.name, label: m.name === q.laptopName ? "Built-in display" : ((String(m.make || "") + " " + String(m.model || "")).trim() || m.name),
                   detail: m.disabled ? "Off" : (m.mirrorOf && m.mirrorOf !== "none" ? "Mirroring " + m.mirrorOf
                     : Math.round(m.width / m.scale) + " × " + Math.round(m.height / m.scale) + " · " + Math.round(m.refreshRate) + " Hz · " + Math.round(m.scale * 100) + "%"),
                   off: !!m.disabled }
        })
        delegate: QsMenuItem {
          required property var modelData
          icon: modelData.name === q.laptopName ? Icons.laptop : Icons.monitor
          text: modelData.label
          detail: modelData.detail + " · " + modelData.name
          dim: modelData.off
          tip: "Display settings"
          onClicked: q.openPage("displays")
        }
      }
      QsMenuItem {
        visible: q.displays.length <= 1
        text: "Plug in a display to extend or mirror"
        detail: "It shows up here and on the Displays page"
        clickable: false
        dim: true
      }
      QsMenuItem {
        visible: q.displays.length > 1 && q.laptopName !== ""
        separatorAbove: true
        text: "Mirror built-in display"
        checked: q.displays.some(function(m) { return m.mirrorOf && m.mirrorOf !== "none" })
        onClicked: q.qc.runner.run(["omarchy-hyprland-monitor-internal-mirror", "toggle"], function() { q.refreshSlow() })
      }
      QsMenuItem {
        visible: q.displays.length > 1 && q.laptopName !== ""
        text: "Use built-in display"
        checked: q.displays.some(function(m) { return m.name === q.laptopName && !m.disabled })
        onClicked: q.qc.runner.run(["omarchy-hyprland-monitor-internal", "toggle"], function() { q.refreshSlow() })
      }
      QsMenuItem { icon: Icons.monitor; text: "Identify Displays"; separatorAbove: true; onClicked: q.qc.identifyDisplays() }
      QsMenuItem { text: "Arrange Displays…"; onClicked: q.openPage("displays") }
    }
  }

  Component {
    id: nightMenu
    QsMenu {
      icon: Icons.nightlight
      title: "Night Light"
      QsMenuItem {
        text: "Sunset to sunrise"
        detail: q.nl.hasLocation ? q.hm12(q.nl.sunset) + " – " + q.hm12(q.nl.sunrise) + " at your location" : "Needs your location (none saved yet)"
        checked: q.nl.mode === "sun"
        clickable: !!q.nl.hasLocation
        dim: !q.nl.hasLocation
        onClicked: q.nightSet(["mode=sun"])
      }
      QsMenuItem {
        text: "Custom hours"
        detail: q.hm12(q.nl.start) + " – " + q.hm12(q.nl.end)
        checked: q.nl.mode === "custom"
        onClicked: q.nightSet(["mode=custom"])
      }
      QsMenuItem {
        text: "No schedule"
        detail: "Only when you turn it on here"
        checked: q.nl.mode === "manual"
        onClicked: q.nightSet(["mode=manual"])
      }
      Repeater {
        model: q.nl.mode === "custom" ? [{ k: "start", t: "Turns on" }, { k: "end", t: "Turns off" }] : []
        delegate: Item {
          required property var modelData
          width: parent ? parent.width : 0
          height: Style.space(40)
          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.t
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            QsRoundButton {
              width: Style.space(30)
              icon: String.fromCodePoint(0xF0374)
              tip: "30 minutes earlier"
              onClicked: q.nightSet([modelData.k + "=" + q.shiftTime(q.nl[modelData.k], -30)])
            }
            Text {
              width: Style.space(78)
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignHCenter
              text: q.hm12(q.nl[modelData.k])
              color: Color.menu.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            QsRoundButton {
              width: Style.space(30)
              icon: String.fromCodePoint(0xF0415)
              tip: "30 minutes later"
              onClicked: q.nightSet([modelData.k + "=" + q.shiftTime(q.nl[modelData.k], 30)])
            }
          }
        }
      }
      Text {
        leftPadding: Style.space(10)
        topPadding: Style.space(8)
        text: "Warmth: " + (q.nl.temp || 4500) + " K"
        color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }
      QsSlider {
        width: parent ? parent.width : 0
        icon: String.fromCodePoint(0xF050F)
        iconTip: "Warmth"
        value: (6000 - (q.nl.temp || 4500)) / 3500
        valueTip: "Warmth " + (q.nl.temp || 4500) + " K (lower is warmer)"
        onCommitted: function(v) {
          var t = Math.round((6000 - v * 3500) / 100) * 100
          q.nightSet(["temp=" + t])
          if (q.nightOn) q.qc.runner.run(["hyprctl", "hyprsunset", "temperature", String(t)], null)
        }
      }
      Text {
        leftPadding: Style.space(10)
        topPadding: Style.space(8)
        text: "Brightness while on: " + (q.nl.dim || 100) + "%"
        color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }
      QsSlider {
        width: parent ? parent.width : 0
        icon: Icons.brightness
        iconTip: "Brightness while on"
        value: ((q.nl.dim || 100) - 30) / 70
        valueTip: "Brightness while on " + (q.nl.dim || 100) + "%"
        onCommitted: function(v) {
          var d = Math.round(30 + v * 70)
          q.nightSet(["dim=" + d])
          if (q.nightOn) q.qc.runner.run(["hyprctl", "hyprsunset", "gamma", String(d)], null)
        }
      }
      QsMenuItem { text: "Display Settings"; separatorAbove: true; onClicked: q.openPage("displays") }
    }
  }

  Component {
    id: powerMenu
    QsMenu {
      icon: Icons.bolt
      title: "Power Mode"
      Repeater {
        model: q.profiles
        delegate: QsMenuItem {
          required property var modelData
          text: modelData === "power-saver" ? "Power Saver" : modelData === "performance" ? "Performance" : "Balanced"
          detail: modelData === "power-saver" ? "Reduced performance and power usage" : modelData === "performance" ? "High performance and power usage" : "Standard performance and power usage"
          checked: q.profile === modelData
          onClicked: q.setProfile(modelData)
        }
      }
      QsMenuItem { text: "Power Settings"; separatorAbove: true; onClicked: q.openPage("power") }
    }
  }

  Component {
    id: layoutMenu
    QsMenu {
      icon: Icons.windows
      title: "Window Layout"
      Repeater {
        model: [{ v: "dwindle", t: "Dwindle", d: "Split the focused window" }, { v: "master", t: "Master", d: "One main window, stack beside it" }, { v: "scrolling", t: "Scrolling", d: "Columns on an endless strip" }]
        delegate: QsMenuItem {
          required property var modelData
          text: modelData.t
          detail: modelData.d + (q.wsLayout === modelData.v ? " · this workspace" : "")
          checked: q.defaultLayout === modelData.v
          onClicked: {
            q.defaultLayout = modelData.v
            q.qc.hypr.set("general:layout", modelData.v)
          }
        }
      }
      QsMenuItem { icon: Icons.refresh; text: "Cycle This Workspace"; separatorAbove: true; onClicked: q.pillToggle("layout") }
      QsMenuItem { text: "Toggle Window Gaps"; onClicked: q.qc.runner.run(["omarchy-hyprland-window-gaps-toggle"], null) }
      QsMenuItem { text: "Windows & Layout Settings"; separatorAbove: true; onClicked: q.openPage("windows") }
    }
  }

  Component {
    id: printerMenu
    QsMenu {
      icon: Icons.printer
      title: "Printers"
      QsMenuItem { visible: q.printers.length === 0; text: "No printers"; clickable: false; dim: true }
      Repeater {
        model: q.printers
        delegate: QsMenuItem {
          required property var modelData
          icon: Icons.printer
          text: modelData.name.replace(/_/g, " ")
          detail: (modelData.isDefault ? "Default · " : "") + (modelData.state || "")
          checked: modelData.isDefault
          // Sets this user's default; no admin rights needed.
          onClicked: q.qc.runner.run(["lpoptions", "-d", modelData.name], function() { q.refreshSlow() })
        }
      }
      Repeater {
        model: q.jobs
        delegate: QsMenuItem {
          required property var modelData
          required property int index
          separatorAbove: index === 0
          icon: Icons.dots
          text: "Job " + modelData.id
          detail: modelData.user + (modelData.size ? " · " + modelData.size + " bytes" : "")
          trailing: "Cancel"
          onClicked: q.qc.runner.run(["cancel", modelData.id], function() { q.refreshSlow() })
        }
      }
      QsMenuItem { icon: String.fromCodePoint(0xF0415); text: "Add a Printer…"; separatorAbove: true; onClicked: q.openPage("printers") }
      QsMenuItem { text: "Printers & Scanners Settings"; onClicked: q.openPage("printers") }
    }
  }

  Component {
    id: recordMenu
    QsMenu {
      icon: String.fromCodePoint(0xF0A1C)
      title: "Screen Recording"
      active: q.recording
      QsMenuItem { visible: q.recording; icon: String.fromCodePoint(0xF04DB); text: "Stop Recording"; onClicked: q.stopRecording() }
      QsMenuItem { visible: !q.recording; icon: String.fromCodePoint(0xF0A1C); text: "Record a Region"; detail: "Drag to pick the area"; onClicked: q.startRecording(false) }
      QsMenuItem { visible: !q.recording; icon: Icons.monitor; text: "Record the Full Screen"; onClicked: q.startRecording(true) }
      QsMenuItem { visible: !q.recording; separatorAbove: true; icon: Icons.speaker; text: "Desktop Audio"; checked: q.recDesktopAudio; onClicked: q.recDesktopAudio = !q.recDesktopAudio }
      QsMenuItem { visible: !q.recording; icon: Icons.microphone; text: "Microphone"; checked: q.recMic; onClicked: q.recMic = !q.recMic }
      QsMenuItem { visible: !q.recording; icon: String.fromCodePoint(0xF0100); text: "Webcam Overlay"; checked: q.recWebcam; onClicked: q.recWebcam = !q.recWebcam }
      QsMenuItem { separatorAbove: true; text: "Recordings Folder"; trailing: String.fromCodePoint(0xF03CC); tip: "Opens your videos folder"
        onClicked: q.qc.launch(["xdg-open", Quickshell.env("OMARCHY_SCREENRECORD_DIR") || Quickshell.env("XDG_VIDEOS_DIR") || (Quickshell.env("HOME") + "/Videos")], 0) }
    }
  }

  Component {
    id: reminderMenu
    QsMenu {
      icon: String.fromCodePoint(0xF0020)
      title: "Reminders"
      active: q.reminders.length > 0
      QsMenuItem { visible: q.reminders.length === 0; text: "No reminders set"; clickable: false; dim: true }
      Repeater {
        model: q.reminders
        delegate: QsMenuItem {
          required property var modelData
          icon: String.fromCodePoint(0xF0954)
          text: String(modelData.label || modelData.message || "Reminder")
          detail: "at " + String(modelData.atTime || "") + " · in " + String(modelData.remaining || "")
          trailing: String.fromCodePoint(0xF0156)
          tip: "Cancel this reminder"
          onClicked: q.cancelReminder(String(modelData.timer || ""))
        }
      }
      Row {
        width: parent ? parent.width : 0
        spacing: Style.space(6)
        topPadding: Style.space(6)
        Repeater {
          model: [5, 15, 30, 60]
          delegate: Button {
            required property var modelData
            text: modelData < 60 ? modelData + " min" : "1 hour"
            bordered: true
            foreground: Color.menu.text
            fontSize: Style.font.bodySmall
            property bool ccFocusable: visible
            function ccActivate() { clicked() }
            onClicked: q.addReminder(modelData, reminderText.text)
          }
        }
      }
      Row {
        width: parent ? parent.width : 0
        spacing: Style.space(6)
        topPadding: Style.space(6)
        bottomPadding: Style.space(4)
        TextField {
          id: reminderText
          width: parent.width - reminderMinutes.width - addBtn.width - Style.space(12)
          placeholderText: "Message (optional)"
          foreground: Color.menu.text
          property bool ccFocusable: visible
          property bool hasCursor: false
          function ccActivate() { forceActiveFocus() }
          Keys.onReturnPressed: addBtn.clicked()
        }
        TextField {
          id: reminderMinutes
          width: Style.space(64)
          placeholderText: "min"
          foreground: Color.menu.text
          property bool ccFocusable: visible
          property bool hasCursor: false
          function ccActivate() { forceActiveFocus() }
          Keys.onReturnPressed: addBtn.clicked()
        }
        Button {
          id: addBtn
          text: "Set"
          bordered: true
          foreground: Color.menu.text
          fontSize: Style.font.bodySmall
          property bool ccFocusable: visible
          function ccActivate() { clicked() }
          onClicked: {
            if (reminderMinutes.text.trim() === "") { q.qc.toast("Enter minutes, or use a preset"); return }
            q.addReminder(reminderMinutes.text.trim(), reminderText.text)
            reminderText.text = ""; reminderMinutes.text = ""
            q.qc.focusKeys()
          }
        }
      }
      QsMenuItem { visible: q.reminders.length > 1; separatorAbove: true; text: "Clear All Reminders"
        onClicked: q.qc.runner.run(["omarchy-reminder", "clear"], function() { q.refreshSlow() }) }
    }
  }

  Component {
    id: sudoMenu
    QsMenu {
      icon: String.fromCodePoint(0xF0FC5)
      title: "Passwordless Sudo"
      active: q.sudoFree
      QsMenuItem {
        visible: q.sudoFree
        icon: Icons.lock
        text: "Require a Password Again"
        detail: q.sudoBusy ? "Disabling…" : "Revoke the passwordless grant now"
        onClicked: q.disableSudo()
      }
      QsMenuItem { visible: !q.sudoFree; text: "Allow any process run as you to use sudo without a password."; clickable: false; dim: true }
      QsMenuItem { visible: !q.sudoFree; icon: Icons.clock; text: "For 15 Minutes"; trailing: String.fromCodePoint(0xF03CC); tip: "Confirms and asks for your password in a terminal"; onClicked: q.enableSudo("15") }
      QsMenuItem { visible: !q.sudoFree; icon: Icons.clock; text: "For 1 Hour"; trailing: String.fromCodePoint(0xF03CC); tip: "Confirms and asks for your password in a terminal"; onClicked: q.enableSudo("60") }
      QsMenuItem { visible: !q.sudoFree; icon: Icons.clock; text: "For 1 Day"; trailing: String.fromCodePoint(0xF03CC); tip: "Confirms and asks for your password in a terminal"; onClicked: q.enableSudo("1440") }
      QsMenuItem { visible: !q.sudoFree; icon: String.fromCodePoint(0xF0026); text: "Permanently"; detail: "Weakens security until you turn it off"; trailing: String.fromCodePoint(0xF03CC); tip: "Confirms and asks for your password in a terminal"; onClicked: q.enableSudo("permanent") }
    }
  }

  Component {
    id: scannerMenu
    QsMenu {
      icon: String.fromCodePoint(0xF06AB)
      title: "Scanners"
      QsMenuItem { visible: q.scanning; text: "Searching for scanners…"; detail: "Network scanners can take a few seconds"; clickable: false; dim: true }
      QsMenuItem { visible: !q.scanning && q.scannedOnce && q.scanners.length === 0; text: "No scanners found"; clickable: false; dim: true }
      Repeater {
        model: q.scanning ? [] : q.scanners
        delegate: QsMenuItem {
          required property var modelData
          icon: String.fromCodePoint(0xF06AB)
          text: modelData.label
          detail: modelData.device.split(":")[0]
          trailing: "Scan"
          onClicked: q.qc.launch(["simple-scan", modelData.device], 0)
        }
      }
      QsMenuItem { icon: Icons.refresh; text: "Search Again"; separatorAbove: true; clickable: !q.scanning; onClicked: q.scanForScanners() }
      QsMenuItem { text: "Open Document Scanner"; onClicked: q.qc.launch(["simple-scan"], 0) }
      QsMenuItem { icon: String.fromCodePoint(0xF0415); text: "Add a Scanner…"; onClicked: q.openPage("printers") }
    }
  }
}
