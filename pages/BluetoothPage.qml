import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Bluetooth adapter and devices, live from BlueZ. Scans while the page is open.
CcPage {
  id: page

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool powered: !!adapter && adapter.enabled
  readonly property var deviceObjects: Bluetooth.devices ? Bluetooth.devices.values : []

  // Primitive rows (see WifiPage): actions resolve the device by address.
  readonly property var rows: {
    var list = []
    for (var i = 0; i < deviceObjects.length; i++) {
      var d = deviceObjects[i]
      if (!d || !d.address) continue
      list.push({
        address: String(d.address), name: String(d.name || d.deviceName || d.address),
        icon: String(d.icon || ""), connected: !!d.connected,
        paired: !!(d.paired || d.bonded), trusted: !!d.trusted,
        battery: d.batteryAvailable ? Math.round(d.battery * 100) : -1,
        busy: d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting || !!d.pairing
      })
    }
    list.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      return a.name.localeCompare(b.name)
    })
    return list
  }
  readonly property var myDevices: rows.filter(function(r) { return r.paired || r.connected })
  // Unnamed devices advertise only their address (often with dashes); they
  // are beacons and trackers more often than anything one would pair.
  readonly property var nearby: rows.filter(function(r) {
    return !r.paired && !r.connected && !/^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i.test(r.name)
  })

  property var pending: ({})

  function restartBluetooth() {
    cc.toast("Restarting Bluetooth…")
    cc.runner.run(["omarchy-restart-bluetooth"], function(code) { page.cc.toast(code === 0 ? "Bluetooth restarted" : "Bluetooth restart failed") })
  }

  function act(row, action) {
    var p = {}; for (var k in pending) p[k] = pending[k]
    p[row.address] = action
    pending = p
    cc.runner.run(["omarchy-bluetooth-device", action, row.address], function(code) {
      var q = {}; for (var k in page.pending) if (k !== row.address) q[k] = page.pending[k]
      page.pending = q
      if (code !== 0) page.cc.toast("Could not " + action + " " + row.name)
    })
  }

  function subtitleFor(r) {
    var parts = []
    if (pending[r.address]) parts.push(pending[r.address] === "pair" ? "Pairing…" : pending[r.address] === "connect" ? "Connecting…" : pending[r.address] === "disconnect" ? "Disconnecting…" : "Removing…")
    else if (r.busy) parts.push("Working…")
    else parts.push(r.connected ? "Connected" : (r.paired ? "Not connected" : "Not paired"))
    if (r.battery >= 0) parts.push("Battery " + r.battery + "%")
    return parts.join(" · ")
  }

  // Discovery while the page is up; switched off again when it goes.
  Timer {
    interval: 500
    running: page.powered && !page.adapter.discovering
    onTriggered: if (page.adapter) page.adapter.discovering = true
  }
  Component.onDestruction: if (adapter && adapter.discovering) adapter.discovering = false

  CcGroup {
    visible: !page.adapter
    CcRow {
      icon: Icons.bluetoothOff
      title: "No Bluetooth adapter"
      subtitle: "The adapter may be blocked or the service stopped"
      CcButton { text: "Restart Bluetooth"; onClicked: page.restartBluetooth() }
    }
  }

  CcGroup {
    visible: !!page.adapter
    CcSwitchRow {
      icon: page.powered ? Icons.bluetooth : Icons.bluetoothOff
      title: "Bluetooth"
      subtitle: !page.powered ? "Off" : "Visible as “" + (page.adapter.name || "this computer") + "”" + (page.adapter.discovering ? " · searching for devices" : "")
      checked: page.powered
      // omarchy-bluetooth-power remembers the choice across reboots.
      onToggled: page.cc.runner.run(["omarchy-bluetooth-power", page.powered ? "off" : "on"], null)
    }
    CcSwitchRow {
      visible: page.powered
      title: "Discoverable"
      subtitle: "Let other devices find this computer"
      checked: !!page.adapter && page.adapter.discoverable
      onToggled: page.adapter.discoverable = !page.adapter.discoverable
    }
  }

  CcGroup {
    visible: page.powered
    title: "My devices"
    subtitle: page.myDevices.length === 0 ? "No paired devices yet" : ""
    Repeater {
      model: page.myDevices
      delegate: CcRow {
        required property var modelData
        icon: Icons.bluetoothDevice(modelData.icon)
        iconColor: modelData.connected ? page.cc.accent : page.cc.fg
        title: modelData.name
        subtitle: page.subtitleFor(modelData)
        clickable: !page.pending[modelData.address]
        onClicked: page.act(modelData, modelData.connected ? "disconnect" : "connect")
        CcButton {
          text: modelData.connected ? "Disconnect" : "Connect"
          onClicked: page.act(modelData, modelData.connected ? "disconnect" : "connect")
        }
        CcButton {
          text: "Forget"
          onClicked: page.act(modelData, "forget")
        }
      }
    }
  }

  CcGroup {
    visible: page.powered
    title: "Nearby devices"
    subtitle: page.nearby.length === 0 ? (page.adapter && page.adapter.discovering ? "Searching… put your device in pairing mode" : "") : "Click a device to pair and connect"
    Repeater {
      model: page.nearby
      delegate: CcRow {
        required property var modelData
        icon: Icons.bluetoothDevice(modelData.icon)
        title: modelData.name
        subtitle: page.subtitleFor(modelData)
        clickable: !page.pending[modelData.address]
        onClicked: page.act(modelData, "pair")
      }
    }
  }

  CcGroup {
    title: "Troubleshooting"
    CcRow {
      icon: Icons.refresh
      title: "Restart Bluetooth"
      subtitle: "Unblock the radio and restart the service"
      clickable: true
      onClicked: page.restartBluetooth()
    }
  }
}
