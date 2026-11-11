import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

CcPage {
  id: page

  readonly property var devices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: {
    for (var i = 0; i < devices.length; i++) if (devices[i] && devices[i].type === DeviceType.Wifi) return devices[i]
    return null
  }
  readonly property bool enabled: Networking.wifiEnabled
  readonly property var networkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  // Primitive rows only: a live WifiNetwork held by a delegate can be destroyed
  // by NetworkManager churn mid-incubation and crash the shell. Actions look
  // the object up again by name (networkFor).
  readonly property var networks: {
    var list = []
    for (var i = 0; i < networkObjects.length; i++) {
      var n = networkObjects[i]
      if (!n || !n.name) continue
      list.push({ ssid: String(n.name), connected: !!n.connected, known: !!n.known,
                  signal: n.signalStrength || 0, security: n.security, changing: !!n.stateChanging })
    }
    list.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return b.signal - a.signal
    })
    return list
  }
  readonly property var connected: networks.length > 0 && networks[0].connected ? networks[0] : null

  function networkFor(ssid) {
    for (var i = 0; i < networkObjects.length; i++)
      if (networkObjects[i] && networkObjects[i].name === ssid) return networkObjects[i]
    return null
  }

  property string passwordFor: ""
  property var details: ({})
  property var band: ({})

  function securityLabel(n) {
    switch (n.security) {
    case WifiSecurityType.Open: return "Open"
    case WifiSecurityType.Owe: return "Enhanced Open"
    case WifiSecurityType.Wep: return "WEP"
    case WifiSecurityType.WpaPsk: return "WPA"
    case WifiSecurityType.Wpa2Psk: return "WPA2"
    case WifiSecurityType.Sae: return "WPA3"
    case WifiSecurityType.Wpa2Eap:
    case WifiSecurityType.WpaEap:
    case WifiSecurityType.Wpa3SuiteB192: return "Enterprise"
    default: return "Secured"
    }
  }
  function needsPassword(n) {
    return !n.known && n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe
  }
  function activate(n) {
    if (n.connected) return
    if (needsPassword(n)) { passwordFor = (passwordFor === n.ssid ? "" : n.ssid); return }
    var obj = networkFor(n.ssid)
    if (obj) obj.connect()
  }
  function act(ssid, fn) {
    var obj = networkFor(ssid)
    if (obj) fn(obj)
  }

  function refreshDetails() {
    cc.runner.run(["omarchy-network-status", "--verbose"], function(code, out) {
      var d = {}
      String(out).split("\n").forEach(function(l) { var t = l.split("\t"); if (t.length >= 2) d[t[0]] = t.slice(1).join("\t") })
      page.details = d
    })
    cc.runner.run(["omarchy-network-band"], function(code, out) {
      var d = {}
      String(out).split("\n").forEach(function(l) { var t = l.split("\t"); if (t.length >= 2) d[t[0]] = t[1] })
      page.band = d
    })
  }

  onConnectedChanged: detailsLater.restart()
  Timer { id: detailsLater; interval: 800; onTriggered: page.refreshDetails() }
  Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: page.refreshDetails() }

  // Scan while the page is up, and only then.
  Binding { target: page.wifiDevice; property: "scannerEnabled"; value: true; when: page.wifiDevice !== null && page.enabled }
  Component.onDestruction: if (wifiDevice) wifiDevice.scannerEnabled = false

  CcGroup {
    CcSwitchRow {
      icon: page.enabled ? Icons.wifi : Icons.wifiOff
      title: "Wi-Fi"
      subtitle: !page.wifiDevice ? "No Wi-Fi adapter found"
        : !page.enabled ? "Off"
        : page.connected ? "Connected to " + page.connected.ssid : "Not connected"
      checked: page.enabled
      onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
    }
  }

  CcGroup {
    visible: page.connected !== null
    title: "Current connection"
    header: [
      CcButton { text: "Disconnect"; onClicked: if (page.connected) page.act(page.connected.ssid, function(o) { o.disconnect() }) }
    ]
    CcRow {
      icon: Icons.wifiStrength(page.connected ? page.connected.signal : 0)
      title: page.connected ? page.connected.ssid : ""
      subtitle: {
        var d = page.details, parts = []
        if (d.signal_dbm) parts.push(d.signal_dbm + " dBm")
        if (d.freq) parts.push((Number(d.freq) / 1000).toFixed(1) + " GHz")
        if (page.connected) parts.push(page.securityLabel(page.connected))
        return parts.join(" · ")
      }
    }
    CcRow {
      title: "IP address"
      subtitle: page.details.ip ? page.details.ip + "/" + (page.details.prefix || "") : "—"
      clickable: !!page.details.ip
      onClicked: page.cc.copy(page.details.ip)
      CcText { text: "Copy"; color: Qt.rgba(page.cc.fg.r, page.cc.fg.g, page.cc.fg.b, 0.62); font.pixelSize: Style.font.caption; visible: !!page.details.ip }
    }
    CcRow { title: "Gateway"; subtitle: page.details.gateway || "—" }
    CcRow { title: "Interface"; subtitle: page.details.iface || (page.wifiDevice ? page.wifiDevice.name : "—") }
    CcChoiceRow {
      visible: !!page.band.available
      title: "Band"
      subtitle: page.band.band ? "Currently on " + page.band.band + " GHz" : ""
      options: ["auto"].concat(String(page.band.available || "").split(" ").filter(function(x) { return x !== "" }))
        .map(function(b) { return { value: b, label: b === "auto" ? "Auto" : b + " GHz" } })
      value: page.band.selected || "auto"
      onPicked: function(v) { page.cc.runner.run(["omarchy-network-band", v], function() { page.refreshDetails() }) }
    }
  }

  CcSpeedTest { visible: page.connected !== null }

  CcGroup {
    visible: page.enabled && page.wifiDevice !== null
    title: "Visible networks"
    subtitle: page.networks.length === 0 ? "Scanning…" : ""

    Repeater {
      model: page.networks.filter(function(n) { return !n.connected })
      delegate: Column {
        id: netItem
        required property var modelData
        required property int index
        width: parent ? parent.width : 0

        CcRow {
          separator: netItem.index > 0
          icon: Icons.wifiStrength(netItem.modelData.signal)
          title: netItem.modelData.ssid
          subtitle: (netItem.modelData.changing ? "Connecting…  " : "")
            + (netItem.modelData.known ? "Saved · " : "") + page.securityLabel(netItem.modelData)
            + " · " + Math.round(netItem.modelData.signal * 100) + "%"
          clickable: true
          onClicked: page.activate(netItem.modelData)
          CcText {
            visible: page.needsPassword(netItem.modelData)
            text: Icons.lock
            color: Qt.rgba(page.cc.fg.r, page.cc.fg.g, page.cc.fg.b, 0.62)
            font.family: Style.font.family
          }
          CcButton {
            visible: netItem.modelData.known
            text: "Forget"
            onClicked: page.act(netItem.modelData.ssid, function(o) { o.forget() })
          }
        }

        Item {
          visible: page.passwordFor === netItem.modelData.ssid
          width: parent.width
          height: visible ? pwRow.implicitHeight + Style.spacing.xl * 2 : 0
          Row {
            id: pwRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(48)
            spacing: Style.spacing.lg
            TextField {
              id: pw
              width: Style.space(260)
              password: true
              placeholderText: "Password"
              foreground: page.cc.fg
              onVisibleChanged: if (visible) forceActiveFocus()
              Keys.onReturnPressed: connectBtn.clicked()
            }
            CcButton {
              id: connectBtn
              text: "Connect"
              onClicked: {
                if (pw.text.length === 0) return
                var secret = pw.text
                page.act(netItem.modelData.ssid, function(o) { o.connectWithPsk(secret) })
                pw.text = ""
                page.passwordFor = ""
              }
            }
            CcButton { text: "Cancel"; onClicked: { pw.text = ""; page.passwordFor = "" } }
          }
        }
      }
    }
  }

  CcGroup {
    title: "More"
    CcRow {
      icon: Icons.cog
      title: "Advanced network settings"
      subtitle: "Hidden networks, enterprise Wi-Fi and saved profiles in nmtui"
      clickable: true
      external: true
      tip: "Opens nmtui in a terminal"
      onClicked: page.cc.launchTerminal("nmtui")
    }
    CcRow {
      icon: Icons.refresh
      title: "Restart Wi-Fi"
      subtitle: "Unblock and restart the Wi-Fi service"
      clickable: true
      onClicked: {
        page.cc.toast("Restarting Wi-Fi…")
        page.cc.runner.run(["omarchy-restart-wifi"], function(code) { page.cc.toast(code === 0 ? "Wi-Fi restarted" : "Wi-Fi restart failed") })
      }
    }
  }
}
