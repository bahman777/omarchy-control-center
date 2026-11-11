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

// GNOME-style Quick Settings: header buttons, sliders, and a grid of pill
// toggles whose menus open in place. Lives only while the panel is open, so
// all polling stops when it closes.
Item {
  id: q

  // The bar widget (BarWidget.qml): runner, close(), launch(), openSettings().
  required property var qc

  implicitHeight: col.implicitHeight
  property string expanded: qc.menu
  Connections { target: q.qc; function onMenuChanged() { if (q.qc.menu) q.expanded = q.qc.menu } }
  function toggleMenu(id) { expanded = expanded === id ? "" : id }

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
  readonly property var idle: qc.firstParty("omarchy.idle")
  readonly property var night: qc.firstParty("omarchy.nightlight")
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
    list.push({ id: "night", icon: Icons.nightlight, title: "Night Light", subtitle: night && night.enabled ? "On" : "Off", active: !!night && night.enabled, hasMenu: false })
    list.push({ id: "dnd", icon: dnd === "on" ? Icons.bellOff : Icons.bell, title: "Do Not Disturb", subtitle: dnd === "" ? "Unavailable" : dnd === "on" ? "On" : "Off", active: dnd === "on", hasMenu: false })
    list.push({ id: "awake", icon: String.fromCodePoint(0xF0176), title: "Stay Awake", subtitle: idle && idle.stayAwake ? "Idle paused" : "Off", active: !!idle && idle.stayAwake, hasMenu: false })
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
    case "night": if (night) night.setNightlight(!night.enabled); break
    case "dnd": qc.runner.run(["omarchy-toggle-notification-silencing"], function() { q.refreshSlow() }); break
    case "awake": if (idle) idle.setIdleEnabled(idle.stayAwake); break
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
        MouseArea { id: batMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: q.qc.openSettings("power") }
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)
        QsRoundButton { icon: String.fromCodePoint(0xF0100); onClicked: q.qc.launch(["omarchy-capture-screenshot"], 350) }
        QsRoundButton { icon: Icons.cog; onClicked: q.qc.openSettings("") }
        QsRoundButton { icon: Icons.lock; onClicked: q.qc.launch(["omarchy-system-lock"], 150) }
        QsRoundButton { icon: Icons.power; active: q.expanded === "session"; onClicked: q.toggleMenu("session") }
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
        QsMenuItem { text: "Sound Settings"; separatorAbove: true; onClicked: q.qc.openSettings("sound") }
      }

      QsSlider {
        visible: q.defaultSource !== null && q.sources.length > 0
        icon: q.defaultSource && q.defaultSource.audio && q.defaultSource.audio.muted ? Icons.microphoneOff : Icons.microphone
        value: q.defaultSource && q.defaultSource.audio ? q.defaultSource.audio.volume : 0
        muted: !!(q.defaultSource && q.defaultSource.audio && q.defaultSource.audio.muted)
        hasMenu: q.sources.length > 0
        expanded: q.expanded === "inputs"
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
        onMoved: function(v) { q.pendingBrightness = v; brightnessApply.restart() }
        onCommitted: function(v) { q.brightness = v; q.pendingBrightness = v; brightnessApply.restart() }
      }
    }

    // ---------------------------------------------------- pill grid
    Column {
      width: parent.width
      spacing: Style.space(10)

      Repeater {
        model: q.pillRows
        delegate: Column {
          id: pairRow
          required property var modelData
          width: parent.width
          spacing: Style.space(10)
          readonly property var ids: modelData.map(function(p) { return p.id })

          Row {
            width: parent.width
            spacing: Style.space(10)
            Repeater {
              model: pairRow.modelData
              delegate: QsPill {
                required property var modelData
                width: (pairRow.width - Style.space(10)) / 2
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
      QsMenuItem { text: "All Networks"; separatorAbove: true; onClicked: q.qc.openSettings("wifi") }
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
      QsMenuItem { text: "Bluetooth Settings"; separatorAbove: true; onClicked: q.qc.openSettings("bluetooth") }
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
      QsMenuItem { text: "Tailscale Settings"; separatorAbove: true; onClicked: q.qc.openSettings("tailscale") }
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
      QsMenuItem { text: "Network Settings"; separatorAbove: true; onClicked: q.qc.openSettings("network") }
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
      QsMenuItem { text: "Power Settings"; separatorAbove: true; onClicked: q.qc.openSettings("power") }
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
      QsMenuItem { text: "Windows & Layout Settings"; separatorAbove: true; onClicked: q.qc.openSettings("windows") }
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
