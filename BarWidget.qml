import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick.Controls
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "quick"
import "Icons.js" as Icons

// GNOME-style status cluster in the bar (network · Bluetooth · volume ·
// battery). Clicking it drops the Quick Settings panel from the bar, like the
// top-right menu in Ubuntu. Every setting lives in that panel: deeper
// settings open as pages inside it, with a back button.
Panel {
  id: root
  moduleName: "io.github.bahman777.control-center"
  ipcTarget: "control-center"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string pluginId: "io.github.bahman777.control-center"
  readonly property var shellApi: bar ? bar.shell : null

  // ------------------------------------------------------------ status glyphs
  readonly property var netDevices: Networking.devices ? Networking.devices.values : []
  readonly property bool wiredUp: netDevices.some(function(d) { return d && d.type === DeviceType.Wired && d.connected })
  readonly property var wifiNet: {
    for (var i = 0; i < netDevices.length; i++) {
      var d = netDevices[i]
      if (!d || d.type !== DeviceType.Wifi || !d.networks) continue
      var nets = d.networks.values
      for (var j = 0; j < nets.length; j++) if (nets[j] && nets[j].connected) return { signal: nets[j].signalStrength || 0, name: nets[j].name || "" }
    }
    return null
  }
  readonly property string netGlyph: wiredUp ? Icons.ethernet
    : !Networking.wifiEnabled ? Icons.wifiOff
    : wifiNet ? Icons.wifiStrength(wifiNet.signal) : String.fromCodePoint(0xF092D)
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool btOn: !!adapter && adapter.enabled
  readonly property bool btConnected: {
    var devs = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devs.length; i++) if (devs[i] && devs[i].connected) return true
    return false
  }
  readonly property var sink: Pipewire.defaultAudioSink
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }
  readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: !!(sink && sink.audio && sink.audio.muted)
  readonly property string volGlyph: muted || vol <= 0.001 ? String.fromCodePoint(0xF075F)
    : vol < 0.34 ? String.fromCodePoint(0xF057F) : vol < 0.67 ? String.fromCodePoint(0xF0580) : Icons.volume
  readonly property var batt: UPower.displayDevice
  readonly property bool hasBattery: !!batt && batt.isPresent
  // Plugged in, whether or not it's charging (a charge limit holds it at 80%).
  readonly property bool plugged: hasBattery && !UPower.onBattery
  readonly property real battPct: hasBattery ? Math.max(0, Math.min(1, batt.percentage)) : 0
  readonly property string batteryGlyph: {
    if (!hasBattery) return ""
    var step = Math.max(0, Math.min(10, Math.round(battPct * 10)))
    var charging = [0xF089C, 0xF089C, 0xF0086, 0xF0087, 0xF0088, 0xF089D, 0xF0089, 0xF089E, 0xF008A, 0xF008B, 0xF0085]
    var discharging = [0xF008E, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079]
    return String.fromCodePoint((plugged ? charging : discharging)[step])
  }
  // The plugin's notification service (NotifyService.qml), once the shell has
  // created it. Looked up on a timer: the shell's service map isn't a binding.
  property var notifService: null
  Timer {
    interval: 1500; repeat: true; triggeredOnStart: true
    running: root.notifService === null
    onTriggered: if (root.shellApi && typeof root.shellApi.serviceFor === "function") root.notifService = root.shellApi.serviceFor(root.pluginId)
  }
  readonly property bool notifActive: !!notifService && notifService.active
  // Bell: always there while Quick Settings handles notifications; a dot when
  // something is unread, crossed out under Do Not Disturb.
  readonly property string notifGlyph: !notifActive ? ""
    : notifService.dnd ? Icons.bellOff : notifService.count > 0 ? String.fromCodePoint(0xF116B) : Icons.bell

  // Tailscale: shown only while connected, like Bluetooth only while on.
  // "" when tailscale isn't installed or answering; otherwise its BackendState.
  property string tsState: ""
  readonly property bool tsUp: tsState === "Running"
  Timer {
    interval: 10000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.runner.run(["tailscale", "status", "--json", "--peers=false"], function(code, out) {
      var st = ""
      try { st = String(JSON.parse(out).BackendState || "") } catch (e) {}
      root.tsState = st
    })
  }

  // Fixed order, left to right: notifications, network, Tailscale, Bluetooth,
  // sound, battery. Network, sound and battery are always shown; the others
  // only when they're on.
  // Music note while a player is playing (playerctld only mirrors others).
  readonly property var playing: {
    var ps = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < ps.length; i++) if (ps[i] && ps[i].isPlaying && String(ps[i].dbusName || "").indexOf("playerctld") < 0) return ps[i]
    return null
  }
  // Audio output switch used by the Sound menu and page (see tools/audio-output.sh).
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  function setAudioOutput(id, name) { runner.run(["bash", pluginDir + "/tools/audio-output.sh", String(id), String(name)], null) }

  // The Now Playing card stays for 30 s after the music pauses or stops, then
  // goes away. Kept here because the panel's contents are rebuilt on open.
  property bool musicLinger: false
  // Last track the Now Playing card showed (see quick/NowPlaying.qml).
  property var lastTrack: null
  onPlayingChanged: {
    if (playing) { musicLinger = false; musicLingerTimer.stop() }
    else { musicLinger = true; musicLingerTimer.restart() }
  }
  Timer { id: musicLingerTimer; interval: 30000; onTriggered: root.musicLinger = false }
  readonly property bool showNowPlaying: !!playing || musicLinger

  // ------------------------------------------------------------ privacy
  // Apps using the camera / microphone right now (tools/privacy.sh), shown as
  // orange icons at the front of the cluster.
  property string camApps: ""
  property string micApps: ""
  Timer {
    interval: 3000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: root.runner.run(["bash", root.pluginDir + "/tools/privacy.sh"], function(code, out) {
      var cam = "", mic = ""
      String(out).split("\n").forEach(function(l) {
        if (l.indexOf("cam:") === 0) cam = l.slice(4).trim()
        else if (l.indexOf("mic:") === 0) mic = l.slice(4).trim()
      })
      root.camApps = cam; root.micApps = mic
    })
  }

  // ------------------------------------------------------------ status colours
  // Taken from the theme's colors.toml (red/orange/green/blue), so they
  // follow theme changes; fallbacks for themes that leave them out.
  property var themeColors: ({})
  FileView {
    id: themeColorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var out = {}, lines = text().split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6,8})"/)
        if (m) out[m[1]] = m[2]
      }
      root.themeColors = out
    }
  }
  Connections { target: Color; function onForegroundChanged() { themeColorsFile.reload() } }
  readonly property color barFg: bar && bar.barForeground ? bar.barForeground : Color.bar.text
  readonly property color dimFg: Qt.rgba(barFg.r, barFg.g, barFg.b, 0.4)
  readonly property color cRed: themeColors.red || "#e5484d"
  readonly property color cOrange: themeColors.orange || "#f5a524"
  readonly property color cGreen: themeColors.green || "#46c35a"
  readonly property color cBlue: themeColors.blue || "#3b8eea"

  readonly property color netColor: wiredUp || wifiNet ? cGreen : dimFg
  readonly property color btColor: btConnected ? cBlue : barFg
  readonly property color volColor: muted ? dimFg : barFg
  readonly property color battColor: plugged ? cGreen : battPct <= 0.10 ? cRed : battPct <= 0.20 ? cOrange : barFg
  readonly property string statusTip: {
    var l = []
    if (camApps !== "") l.push("Camera in use: " + camApps.split(",").join(", "))
    if (micApps !== "") l.push("Microphone in use: " + micApps.split(",").join(", "))
    if (playing) l.push("Playing: " + [playing.trackTitle, playing.trackArtist].filter(function(x) { return x }).join(" — "))
    if (notifActive) l.push("Notifications: " + (notifService.dnd ? "Do Not Disturb" : notifService.count > 0 ? notifService.count + " unread" : "none"))
    l.push(wiredUp ? "Ethernet: connected" : !Networking.wifiEnabled ? "Wi-Fi: off" : wifiNet ? "Wi-Fi: " + (wifiNet.name || "connected") : "Wi-Fi: not connected")
    if (tsState !== "") l.push("Tailscale: " + (tsUp ? "connected" : "not connected"))
    l.push("Bluetooth: " + (!btOn ? "off" : btConnected ? "device connected" : "on"))
    l.push("Volume: " + (muted ? "muted" : Math.round(vol * 100) + "%"))
    if (hasBattery) l.push("Battery: " + Math.round(battPct * 100) + "%" + (!plugged ? "" : batt.state === UPowerDeviceState.Charging ? ", charging" : ", plugged in"))
    l.push("Click: Quick Settings · Right-click: all settings")
    return l.join("\n")
  }

  // ------------------------------------------------------------ helpers for QuickContent
  // Request applied when the panel opens: a menu id ("wifi") or "page:<id>".
  property string menu: ""
  onOpenedChanged: if (!opened) { menu = ""; pageMode = false }
  property bool pageMode: false
  readonly property string buildStamp: String(Date.now())
  readonly property alias runner: runner
  readonly property alias hypr: hypr
  Runner { id: runner }
  HyprOptions { id: hypr; runner: runner }

  function firstParty(id) {
    return shellApi && typeof shellApi.firstPartyServiceFor === "function" ? shellApi.firstPartyServiceFor(id) : null
  }
  function summonPlugin(id, payload) {
    if (shellApi && typeof shellApi.summon === "function") shellApi.summon(id, payload || "{}")
  }
  // Anything that opens a real window or takes the screen closes the panel
  // first, so nothing ever ends up underneath it.
  function launch(argv, delayMs) {
    root.close()
    if (delayMs > 0) Qt.callLater(function() { launchTimer.argv = argv; launchTimer.interval = delayMs; launchTimer.restart() })
    else runner.detach(argv)
  }
  Timer { id: launchTimer; property var argv: []; onTriggered: runner.detach(argv) }
  function openSettings(page) {
    root.menu = ""
    root.menu = "page:" + (page || "index")
    if (!root.opened) root.open()
  }

  // ---- the `cc` API the settings pages (pages/*.qml) are written against
  readonly property var shell: shellApi
  function summon(id, payload) { root.close(); summonPlugin(id, payload) }
  function dismiss() { root.close() }
  // Settings pages open other pages through this (set by QuickContent).
  property var pageOpener: null
  property var nightToggle: null     // (on) → Night Light with your warmth/brightness
  property real calendarDay: 0        // day the Calendar page opens on (0 = today)
  // Theme colours for the settings pages: Color isn't reliably available in
  // a page loaded through a cache-busting URL, so pages read these.
  readonly property color fg: Color.menu.text
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent

  // ---- Identify displays: a big number and name on every screen for 4 s.
  // Numbers follow the arrangement left to right, then top to bottom, the
  // same numbering the Displays page and menu use.
  property bool identifying: false
  function displayNumber(name) {
    var list = Quickshell.screens.slice().sort(function(a, b) { return a.x - b.x || a.y - b.y })
    for (var i = 0; i < list.length; i++) if (list[i].name === name) return i + 1
    return 0
  }
  function identifyDisplays() { root.close(); identifying = true; identifyTimer.restart() }
  Timer { id: identifyTimer; interval: 4000; onTriggered: root.identifying = false }
  Variants {
    model: root.identifying ? Quickshell.screens : []
    PanelWindow {
      required property var modelData
      screen: modelData
      WlrLayershell.namespace: "control-center-identify"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; left: true }
      margins { top: Style.space(60); left: Style.space(60) }
      implicitWidth: idCard.width
      implicitHeight: idCard.height
      color: "transparent"
      Rectangle {
        id: idCard
        width: Math.max(idNum.implicitWidth, idName.implicitWidth) + Style.space(64)
        height: idNum.implicitHeight + idName.implicitHeight + Style.space(40)
        radius: Style.space(18)
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.92)
        border.color: Color.accent
        border.width: 3
        Column {
          anchors.centerIn: parent
          Text {
            id: idNum
            anchors.horizontalCenter: parent.horizontalCenter
            text: String(root.displayNumber(modelData.name))
            color: Color.accent
            font.family: Style.font.menuFamily
            font.pixelSize: Style.space(110)
            font.bold: true
          }
          Text {
            id: idName
            anchors.horizontalCenter: parent.horizontalCenter
            text: (String(modelData.model || "") || modelData.name) + "  ·  " + modelData.name
            color: Color.foreground
            font.family: Style.font.menuFamily
            font.pixelSize: Style.space(20)
          }
        }
      }
    }
  }
  function showMenu(id) { menu = ""; menu = id }
  function openPage(id) { if (pageOpener) pageOpener(id) }
  function launchTerminal(cmd) { launch(["omarchy-launch-floating-terminal-with-presentation", cmd], 0) }
  property string toastText: ""
  function toast(text) { toastText = String(text); toastTimer.restart() }
  Timer { id: toastTimer; interval: 2200 }
  readonly property bool toastVisible: toastTimer.running
  function copy(text) {
    runner.run(["wl-copy", "--", String(text)], null)
    toast("Copied " + text)
  }
  property var keyRoot: null
  function focusKeys() { if (keyRoot) keyRoot.forceActiveFocus() }
  function notify(title, body) {
    runner.run(["omarchy-notification-send", "-g", Icons.cog, String(title), String(body)], null)
  }

  ShellIpc {
    target: root.ipcTarget
    function toggle(): string { root.toggle(); return root.opened ? "open" : "closed" }
    function open(): string { root.open(); return "open" }
    function close(): string { root.close(); return "closed" }
    function settings(page: string): string { root.openSettings(page); return "ok" }
    function identify(): string { root.identifyDisplays(); return "ok" }
    // Open the panel with one menu expanded: wifi, bluetooth, tailscale, vpn,
    // power, layout, printers, scanners, outputs, inputs, session.
    function menu(id: string): string { root.menu = ""; root.menu = id; if (!root.opened) root.open(); return "open" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: true
    fixedWidth: button.vertical ? -1 : statusIcons.implicitWidth + Style.spaceReal(8.5) * 2
    fixedHeight: button.vertical ? statusIcons.implicitHeight + Style.spaceReal(6) * 2 : -1
    fontSize: Style.bar.iconFont
    active: root.opened
    useActiveColor: false
    tooltipText: root.opened ? "" : root.statusTip
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openSettings("index")
      else root.toggle()
    }

    // Left to right: music, notifications, network, Tailscale, Bluetooth,
    // sound, battery. Music only while playing; Bluetooth only while on;
    // Tailscale only when installed.
    Grid {
      id: statusIcons
      anchors.centerIn: parent
      columns: button.vertical ? 1 : 99
      spacing: Style.space(6)
      verticalItemAlignment: Grid.AlignVCenter
      horizontalItemAlignment: Grid.AlignHCenter
      scale: button.pressScale

      BarGlyph { glyph: root.camApps !== "" ? String.fromCodePoint(0xF0567) : ""; color: root.cOrange }
      BarGlyph { glyph: root.micApps !== "" ? Icons.microphone : ""; color: root.cOrange }
      BarGlyph { glyph: root.playing ? Icons.music : ""; color: root.barFg }
      BarGlyph { glyph: root.notifGlyph; color: root.notifActive && !root.notifService.dnd && root.notifService.count > 0 ? root.accent : root.barFg }
      BarGlyph { glyph: root.netGlyph; color: root.netColor }
      // Tailscale's mark: nine dots, the solid ones forming a T.
      Item {
        visible: root.tsState !== ""
        width: Style.bar.iconCanvas; height: Style.bar.iconCanvas
        Grid {
          anchors.centerIn: parent
          columns: 3
          spacing: Math.max(1, Math.round(Style.bar.iconSize / 9))
          Repeater {
            model: [0, 0, 0, 1, 1, 1, 0, 1, 0]
            Rectangle {
              required property int modelData
              readonly property real d: Math.round((Style.bar.iconSize - 2 * Math.max(1, Math.round(Style.bar.iconSize / 9))) / 3)
              width: d; height: d; radius: d / 2
              color: root.tsUp ? root.barFg : root.dimFg
              opacity: modelData ? 1 : 0.35
            }
          }
        }
      }
      BarGlyph { glyph: root.btOn ? (root.btConnected ? Icons.bluetoothConnected : Icons.bluetooth) : ""; color: root.btColor }
      // Speaker plus a small level meter.
      Row {
        spacing: Math.max(1, Math.round(Style.bar.iconSize / 8))
        BarGlyph { glyph: root.volGlyph; color: root.volColor }
        Rectangle {
          visible: !root.muted
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(2, Math.round(Style.bar.iconSize / 5)); height: Style.bar.iconSize
          radius: width / 2
          color: Qt.rgba(root.barFg.r, root.barFg.g, root.barFg.b, 0.25)
          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; radius: parent.radius
            height: Math.max(width, parent.height * Math.min(1, root.vol))
            color: root.vol > 1.001 ? root.cOrange : root.barFg
          }
        }
      }
      Row {
        visible: root.hasBattery
        spacing: Math.max(1, Math.round(Style.bar.iconSize / 6))
        BarGlyph { glyph: root.batteryGlyph; color: root.battColor }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: !button.vertical
          text: Math.round(root.battPct * 100) + "%"
          color: root.battColor
          font.family: button.fontFamily
          font.pixelSize: Math.round(Style.bar.iconFont * 0.85)
          renderType: Text.NativeRendering
        }
      }
    }
  }

  component BarGlyph: OpticalGlyph {
    property string glyph: ""
    visible: glyph !== ""
    width: Style.bar.iconCanvas
    height: Style.bar.iconCanvas
    text: glyph
    fontFamily: button.fontFamily
    fontSize: Style.bar.iconFont
    paintedSize: Style.bar.iconSize
    Behavior on color { ColorAnimation { duration: Style.duration(160) } }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(root.pageMode ? 540 : 470))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    // Keys come here first. Arrows/hjkl move the cursor, Tab walks in
    // order, Enter/Space activate, Left/Right adjust sliders, Esc steps back
    // (page → menu → close). A text field or open dropdown keeps the keys
    // until Esc hands them back.
    content: Item {
      id: keyRoot
      anchors.fill: parent
      implicitHeight: quick.implicitHeight
      focus: true
      Component.onCompleted: root.keyRoot = keyRoot
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var fi = keyRoot.Window.activeFocusItem
        if (fi && fi !== keyRoot) {
          if (event.key === Qt.Key_Escape && fi.popupOpen !== true) { keyRoot.forceActiveFocus(); event.accepted = true }
          return
        }
        var k = event.key, t = event.text
        if (k === Qt.Key_Escape) quick.stepBack()
        else if (k === Qt.Key_Down || t === "j") quick.moveCursor(0, 1)
        else if (k === Qt.Key_Up || t === "k") quick.moveCursor(0, -1)
        else if (k === Qt.Key_Right || t === "l") quick.moveCursor(LayoutMirroring.enabled ? -1 : 1, 0)
        else if (k === Qt.Key_Left || t === "h") quick.moveCursor(LayoutMirroring.enabled ? 1 : -1, 0)
        else if (k === Qt.Key_Tab) quick.stepCursor(1)
        else if (k === Qt.Key_Backtab) quick.stepCursor(-1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) quick.activateCursor()
        else if (k === Qt.Key_Backspace && quick.page !== "") quick.back()
        else if (quick.page === "index" && quick.searchField && t && t.length === 1 && t > " ") {
          quick.searchField.forceActiveFocus()
          quick.searchField.text += t
        } else return
        event.accepted = true
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: quick.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        QuickContent {
          id: quick
          width: parent.width
          qc: root
          flick: flick
        }
      }

      Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.toastVisible
        width: toastLabel.implicitWidth + Style.space(28)
        height: toastLabel.implicitHeight + Style.space(14)
        radius: height / 2
        color: Color.tooltip.background
        border.width: 1
        border.color: Color.tooltip.border
        Text {
          id: toastLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.toastText
          color: Color.tooltip.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
