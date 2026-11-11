import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "quick"
import "Icons.js" as Icons

// GNOME-style status cluster in the bar (network · Bluetooth · volume ·
// battery). Clicking it drops the Quick Settings panel from the bar, like the
// top-right menu in Ubuntu. The full Control Center window opens from its
// gear button or with `omarchy-shell control-center settings [page]`.
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
      for (var j = 0; j < nets.length; j++) if (nets[j] && nets[j].connected) return { signal: nets[j].signalStrength || 0 }
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
  readonly property string batteryGlyph: {
    if (!hasBattery) return ""
    var p = batt.percentage
    if (batt.state === UPowerDeviceState.Charging) return Icons.batteryCharging
    if (p >= 0.95) return Icons.battery
    return String.fromCodePoint(0xF007A + Math.max(0, Math.min(8, Math.floor(p * 10) - 1)))
  }
  readonly property string glyphs: [netGlyph, btOn ? (btConnected ? Icons.bluetoothConnected : Icons.bluetooth) : "", volGlyph, batteryGlyph]
    .filter(function(g) { return g !== "" }).join("  ")

  // ------------------------------------------------------------ helpers for QuickContent
  // Menu to expand when the panel next opens (IPC `menu`).
  property string menu: ""
  onOpenedChanged: if (!opened) menu = ""
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
    root.close()
    summonPlugin(root.pluginId, page ? JSON.stringify({ page: page }) : "{}")
  }
  function notify(title, body) {
    runner.run(["omarchy-notification-send", "-g", Icons.cog, String(title), String(body)], null)
  }

  ShellIpc {
    target: root.ipcTarget
    function toggle(): string { root.toggle(); return root.opened ? "open" : "closed" }
    function open(): string { root.open(); return "open" }
    function close(): string { root.close(); return "closed" }
    function settings(page: string): string { root.openSettings(page); return "ok" }
    // Open the panel with one menu expanded: wifi, bluetooth, tailscale, vpn,
    // power, layout, printers, scanners, outputs, inputs, session.
    function menu(id: string): string { root.menu = id; root.open(); return "open" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyphs
    fontSize: Style.bar.iconFont
    active: root.opened
    useActiveColor: false
    tooltipText: root.opened ? "" : "Quick Settings"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openSettings("")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: quick.implicitHeight
      onCloseRequested: root.close()

      Flickable {
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
        }
      }
    }
  }
}
