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
  function toggleMenu(id) { expanded = expanded === id ? "" : id }

  // ------------------------------------------------------------ in-panel pages
  // Settings open inside the panel as a page with a back button; nothing jumps
  // out to another window.
  property var pageStack: []
  readonly property string page: pageStack.length ? pageStack[pageStack.length - 1] : ""
  readonly property var pageInfo: page === "index" ? { title: "Settings", icon: Icons.cog } : (Pages.find(page) || { title: "", icon: "" })
  function openPage(id) {
    var target = id && (id === "index" || Pages.find(id)) ? id : "index"
    pageStack = pageStack.concat([target])
    expanded = ""
    resetCursor()
  }
  function back() {
    pageStack = pageStack.slice(0, -1)
    resetCursor()
  }
  onPageChanged: { qc.pageMode = page !== ""; if (flick) flick.contentY = 0 }

  // IPC / right-click requests: "wifi" expands a menu, "page:sound" opens a page.
  function applyRequest(req) {
    if (!req) return
    if (req.indexOf("page:") === 0) { pageStack = []; openPage(req.slice(5)) }
    else { pageStack = []; expanded = req }
  }
  Component.onCompleted: applyRequest(qc.menu)
  Connections { target: q.qc; function onMenuChanged() { q.applyRequest(q.qc.menu) } }

  // Esc: leave the page, then collapse the menu, then close the panel.
  function stepBack() {
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
  Timer { id: sinkResolve; interval: 150; running: true
    onTriggered: q.qc.runner.run(["omarchy-audio-output-sink"], function(code, out) { q.volumeSinkName = String(out).trim() }) }
  PwObjectTracker { objects: q.sinks.concat(q.sources) }
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

  // ================================================================ Printers / scanners
  property var printers: []      // [{name, state, isDefault}]
  property var jobs: []          // [{id, user, size, when}]
  property var scanners: []      // [{device, label}]
  property bool scanning: false
  property bool scannedOnce: false

  // ================================================================ refresh
  function refreshSlow() {
    qc.runner.run(["brightnessctl", "-m", "-c", "backlight"], function(code, out) {
      var f = String(out).trim().split(",")
      q.brightness = code === 0 && f.length >= 5 && Number(f[4]) > 0 ? Number(f[2]) / Number(f[4]) : -1
    })
    qc.runner.run(["omarchy-powerprofiles-list", "--active-state"], function(code, out) {
      var list = [], active = ""
      String(out).split("\n").forEach(function(l) { var f = l.split("\t"); if (!f[0]) return; list.push(f[0]); if (f[1] === "1") active = f[0] })
      q.profiles = list; q.profile = active
    })
    qc.runner.run(["omarchy-toggle-idle", "status"], function(code, out) {
      try { q.stayAwake = JSON.parse(out).enabled === true } catch (e) {}
    })
    qc.runner.run(["omarchy-toggle-nightlight", "--status"], function(code, out) {
      try { q.nightOn = JSON.parse(out).enabled === true } catch (e) {}
    })
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
    qc.runner.run(["lpstat", "-e"], function(code, names) {
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
  onExpandedChanged: if (expanded === "scanners" && !scannedOnce) scanForScanners()
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
      list.push({ id: "vpn", icon: Icons.shield, title: "VPN", subtitle: on.length ? on[0].name : "Off", active: on.length > 0, hasMenu: true })
    }
    if (profiles.length > 0)
      list.push({ id: "power", icon: profile === "power-saver" ? String.fromCodePoint(0xF032A) : profile === "performance" ? String.fromCodePoint(0xF04C5) : Icons.bolt,
                  title: "Power Mode", subtitle: profile === "power-saver" ? "Power Saver" : profile === "performance" ? "Performance" : "Balanced",
                  active: profile !== "balanced" && profile !== "", hasMenu: true })
    list.push({ id: "night", icon: Icons.nightlight, title: "Night Light", subtitle: nightOn ? "On" : "Off", active: nightOn, hasMenu: false })
    list.push({ id: "dnd", icon: dnd === "on" ? Icons.bellOff : Icons.bell, title: "Do Not Disturb", subtitle: dnd === "" ? "Unavailable" : dnd === "on" ? "On" : "Off", active: dnd === "on", hasMenu: false })
    list.push({ id: "awake", icon: String.fromCodePoint(0xF0176), title: "Stay Awake", subtitle: stayAwake ? "Screen stays on" : "Off", active: stayAwake, hasMenu: false })
    list.push({ id: "airplane", icon: String.fromCodePoint(0xF001D), title: "Airplane Mode", subtitle: airplane ? "On" : "Off", active: airplane, hasMenu: false })
    list.push({ id: "layout", icon: Icons.windows, title: "Window Layout", subtitle: wsLayout ? wsLayout.charAt(0).toUpperCase() + wsLayout.slice(1) : "—", active: false, hasMenu: true })
    list.push({ id: "printers", icon: Icons.printer, title: "Printers",
                subtitle: jobs.length ? jobs.length + (jobs.length === 1 ? " job" : " jobs") : (printers.filter(function(p) { return p.isDefault })[0] || {}).name || (printers.length ? printers.length + " printers" : "None"),
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
    case "layout": return "Cycle this workspace: dwindle → scrolling → floating"
    case "printers": return "Printers and print jobs"
    case "scanners": return "Find scanners and scan a document"
    case "awake": return p.active ? "Allow the screen to lock and sleep again" : "Keep the screen on: no dimming, lock or screensaver"
    case "airplane": return p.active ? "Turn Wi-Fi and Bluetooth back on" : "Turn off Wi-Fi and Bluetooth"
    case "dnd": return p.active ? "Show notification pop-ups again" : "Silence notification pop-ups"
    default: return (p.active ? "Turn off " : "Turn on ") + p.title
    }
  }
  function menuTipFor(id) {
    return ({ wifi: "Networks", bluetooth: "Devices", tailscale: "Exit node", vpn: "VPN connections",
              power: "Power modes", layout: "Window layout options" })[id] || ""
  }

  readonly property var pillRows: {
    var rows = []
    for (var i = 0; i < pills.length; i += 2) rows.push(pills.slice(i, i + 2))
    return rows
  }

  function pillToggle(id) {
    switch (id) {
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
      qc.runner.run(["omarchy-toggle-nightlight"], function() { q.refreshSlow() })
      break
    case "dnd": qc.runner.run(["omarchy-toggle-notification-silencing"], function() { q.refreshSlow() }); break
    case "awake":
      stayAwake = !stayAwake
      qc.runner.run(["omarchy-toggle-idle", stayAwake ? "stay-awake" : "allow-idle"], function() { q.refreshSlow() })
      break
    case "airplane":
      if (airplane) { Networking.wifiEnabled = true; qc.runner.run(["omarchy-bluetooth-power", "on"], null) }
      else { Networking.wifiEnabled = false; qc.runner.run(["omarchy-bluetooth-power", "off"], null) }
      break
    case "layout": qc.runner.run(["omarchy-hyprland-workspace-layout-toggle"], function() { q.refreshSlow() }); break
    }
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
    visible: q.page === ""

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

    QsMenu {
      visible: q.expanded === "session"
      icon: Icons.power
      title: "Power Off"
      QsMenuItem { icon: Icons.sleep; text: "Suspend"; onClicked: q.qc.launch(["systemctl", "suspend"], 200) }
      QsMenuItem { icon: Icons.restart; text: "Restart…"; onClicked: q.qc.launch(["omarchy-system", "reboot"], 150) }
      QsMenuItem { icon: Icons.power; text: "Power Off…"; onClicked: q.qc.launch(["omarchy-system", "shutdown"], 150) }
      QsMenuItem { icon: Icons.logout; text: "Log Out…"; separatorAbove: true; onClicked: q.qc.launch(["omarchy-system", "logout"], 150) }
    }

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
      QsMenu {
        visible: q.expanded === "outputs"
        icon: Icons.speaker
        title: "Sound Output"
        Repeater {
          model: q.expanded === "outputs" ? q.sinks.map(function(n) { return { id: n.id, name: String(n.name), label: q.nodeLabel(n), icon: q.nodeIcon(n, false) } }) : []
          delegate: QsMenuItem {
            required property var modelData
            icon: modelData.icon
            text: modelData.label
            checked: (q.defaultSink && q.defaultSink.id === modelData.id) || q.volumeSinkName === modelData.name
            onClicked: q.qc.runner.run(["omarchy-audio-output-set-default", String(modelData.id), modelData.name], null)
          }
        }
        QsMenuItem { text: "Sound Settings"; separatorAbove: true; onClicked: q.openPage("sound") }
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
      QsMenu {
        visible: q.expanded === "inputs"
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

          Loader {
            width: parent.width
            active: pairRow.ids.indexOf(q.expanded) >= 0
            visible: active
            sourceComponent: q.expanded === "wifi" ? wifiMenu
              : q.expanded === "bluetooth" ? btMenu
              : q.expanded === "tailscale" ? tsMenu
              : q.expanded === "vpn" ? vpnMenu
              : q.expanded === "power" ? powerMenu
              : q.expanded === "layout" ? layoutMenu
              : q.expanded === "printers" ? printerMenu
              : q.expanded === "scanners" ? scannerMenu : null
          }
        }
      }
    }
  }

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
      QsMenuItem { text: "Printer Settings"; separatorAbove: true; onClicked: q.qc.launch(["system-config-printer"], 0) }
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
    }
  }
}
