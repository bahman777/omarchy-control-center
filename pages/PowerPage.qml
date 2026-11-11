import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Battery (live from UPower), power mode, idle/lock timing and session actions.
CcPage {
  id: page

  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: !!battery && battery.isPresent && battery.isLaptopBattery !== false
  readonly property bool onBattery: UPower.onBattery
  // Stay awake lives in ~/.local/state/omarchy/indicators/stay-awake; the
  // shell's idle service watches it, so the CLI keeps everything in sync.
  property bool stayAwake: false
  function refreshAwake() {
    cc.runner.run(["omarchy-toggle-idle", "status"], function(code, out) {
      try { page.stayAwake = JSON.parse(out).enabled === true } catch (e) {}
    })
  }

  property var profiles: []
  property string activeProfile: ""
  property var idleConfig: ({})
  property bool suspendHidden: false
  property string confirming: ""

  readonly property var peripherals: {
    var list = []
    var devs = UPower.devices ? UPower.devices.values : []
    for (var i = 0; i < devs.length; i++) {
      var d = devs[i]
      // A pen that has never reported (0%) is noise, not a dead battery.
      if (!d || d.isLaptopBattery || !d.isPresent || d.type === UPowerDeviceType.LinePower || !d.model || !(d.percentage > 0)) continue
      list.push({ model: String(d.model), percent: Math.round(d.percentage * 100), kind: "", source: "Bluetooth" })
    }
    return list.concat(logitech)
  }

  // Logitech Unifying/Bolt receiver devices aren't Bluetooth and Linux exposes
  // no battery for them; Solaar reads it over HID++ (takes a few seconds).
  property var logitech: []
  property bool solaarMissing: false
  function refreshLogitech() {
    cc.runner.run(["timeout", "20", "solaar", "show"], function(code, out) {
      if (code === 127) { page.solaarMissing = true; return }
      var list = [], cur = null
      String(out).split("\n").forEach(function(l) {
        var m = /^  (\d+): (.+)$/.exec(l)
        if (m) { cur = { model: m[2].trim(), percent: -1, kind: "", status: "", source: "Logitech receiver" }; list.push(cur); return }
        if (!cur) return
        var k = /^\s+Kind\s*:\s*(\w+)/.exec(l)
        if (k && !cur.kind) cur.kind = k[1]
        var b = /Battery:\s*(\d+)%(?:,\s*BatteryStatus\.(\w+))?/.exec(l)
        if (b && cur.percent < 0) { cur.percent = Number(b[1]); cur.status = (b[2] || "").toLowerCase() }
      })
      page.logitech = list.filter(function(d) { return d.percent >= 0 })
    })
  }
  Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: page.refreshLogitech() }

  function duration(sec) {
    if (!sec || sec <= 0) return ""
    var h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60)
    return h > 0 ? h + " h " + m + " min" : m + " min"
  }

  function batteryText() {
    if (!hasBattery) return ""
    var pct = Math.round(battery.percentage * 100) + "%"
    switch (battery.state) {
    case UPowerDeviceState.Charging: return pct + " · Charging" + (battery.timeToFull > 0 ? " · full in " + duration(battery.timeToFull) : "")
    case UPowerDeviceState.FullyCharged: return pct + " · Fully charged"
    case UPowerDeviceState.PendingCharge: return pct + " · Plugged in, not charging"
    default: return pct + (battery.timeToEmpty > 0 ? " · " + duration(battery.timeToEmpty) + " left" : "")
        + (battery.changeRate > 0 ? " · " + battery.changeRate.toFixed(1) + " W" : "")
    }
  }

  function refreshProfiles() {
    cc.runner.run(["omarchy-powerprofiles-list", "--active-state"], function(code, out) {
      var list = [], active = ""
      String(out).split("\n").forEach(function(l) {
        var f = l.split("\t")
        if (!f[0]) return
        list.push(f[0])
        if (f[1] === "1") active = f[0]
      })
      page.profiles = list
      page.activeProfile = active
    })
    cc.runner.run(["omarchy-toggle-enabled", "suspend-off"], function(code) { page.suspendHidden = code === 0 })
  }
  Component.onCompleted: { refreshProfiles(); refreshAwake() }
  onOnBatteryChanged: refreshProfiles()
  Timer { interval: 4000; running: true; repeat: true; onTriggered: { page.refreshProfiles(); page.refreshAwake() } }

  // Idle timings live in shell.json, which the shell hot-reloads.
  FileView {
    id: shellJson
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { page.idleConfig = JSON.parse(text()).idle || {} } catch (e) {} }
  }
  function setIdle(key, seconds) {
    var n = Math.round(Number(seconds))
    if (["lock", "screensaver"].indexOf(key) < 0 || !isFinite(n) || n < 30 || n > 86400) return
    cc.runner.run(["python3", "-I", "-c",
      "import json,os,sys,tempfile\n"
      + "p=os.path.expanduser('~/.config/omarchy/shell.json')\n"
      + "d=json.load(open(p))\n"
      + "d.setdefault('idle',{})[sys.argv[1]]=int(sys.argv[2])\n"
      + "fd,t=tempfile.mkstemp(dir=os.path.dirname(p))\n"
      + "with os.fdopen(fd,'w') as f: json.dump(d,f,indent=2); f.write('\\n')\n"
      + "os.replace(t,p)\n", key, String(n)], null)
  }
  readonly property var idleChoices: [
    { value: "60", label: "1 minute" }, { value: "120", label: "2 minutes" }, { value: "150", label: "2½ minutes" },
    { value: "300", label: "5 minutes" }, { value: "600", label: "10 minutes" }, { value: "900", label: "15 minutes" },
    { value: "1800", label: "30 minutes" }, { value: "3600", label: "1 hour" }
  ]
  function choiceFor(v) {
    var s = String(v || "")
    for (var i = 0; i < idleChoices.length; i++) if (idleChoices[i].value === s) return idleChoices
    return idleChoices.concat([{ value: s, label: Math.round(Number(s) / 60 * 10) / 10 + " minutes" }])
  }

  function session(action, argv) {
    if (confirming !== action) { confirming = action; confirmReset.restart(); return }
    confirming = ""
    cc.dismiss()
    cc.runner.detach(argv)
  }
  Timer { id: confirmReset; interval: 3000; onTriggered: page.confirming = "" }

  // ------------------------------------------------------------ battery
  CcGroup {
    visible: page.hasBattery
    title: "Battery"
    CcRow {
      icon: page.battery && page.battery.state === UPowerDeviceState.Charging ? Icons.batteryCharging : Icons.battery
      iconColor: page.hasBattery && page.battery.percentage < 0.15 && page.onBattery ? Color.urgent : Color.menu.text
      title: page.onBattery ? "On battery" : "Plugged in"
      subtitle: page.batteryText()
      CcLevelBar { level: page.hasBattery ? page.battery.percentage : 0; low: page.hasBattery && page.battery.percentage < 0.15 && page.onBattery }
    }
    CcRow {
      visible: page.hasBattery && page.battery.healthSupported
      title: "Battery health"
      subtitle: page.hasBattery ? Math.round(page.battery.healthPercentage) + "% of design capacity" : ""
    }
  }

  CcGroup {
    visible: page.peripherals.length > 0
    title: "Device batteries"
    Repeater {
      model: page.peripherals
      delegate: CcRow {
        required property var modelData
        icon: modelData.kind === "mouse" ? Icons.mouse : modelData.kind === "keyboard" ? Icons.keyboard : Icons.bluetoothDevice(modelData.model.toLowerCase())
        iconColor: modelData.percent <= 15 ? Color.urgent : Color.menu.text
        title: modelData.model
        subtitle: modelData.percent + "%" + (modelData.status === "recharging" ? " · charging" : "") + " · " + modelData.source
        CcLevelBar { level: modelData.percent / 100 }
      }
    }
  }

  // ------------------------------------------------------------ power mode
  CcGroup {
    visible: page.profiles.length > 0
    title: "Power mode"
    subtitle: "Remembered separately for " + (page.onBattery ? "battery" : "AC power")
    CcChoiceRow {
      icon: Icons.bolt
      title: "Mode"
      options: page.profiles.map(function(p) {
        return { value: p, label: p === "power-saver" ? "Power saver" : p === "performance" ? "Performance" : "Balanced" }
      })
      value: page.activeProfile
      onPicked: function(v) {
        page.activeProfile = v
        page.cc.runner.run(["omarchy-powerprofiles-set", page.onBattery ? "battery" : "ac", v], function() { page.refreshProfiles() })
      }
    }
  }

  // ------------------------------------------------------------ idle
  CcGroup {
    title: "Screen lock & idle"
    CcSwitchRow {
      icon: Icons.eye
      title: "Stay awake"
      subtitle: "Never dim, lock or start the screensaver while idle"
      checked: page.stayAwake
      onToggled: {
        page.stayAwake = !page.stayAwake
        page.cc.runner.run(["omarchy-toggle-idle", page.stayAwake ? "stay-awake" : "allow-idle"], function() { page.refreshAwake() })
      }
    }
    CcChoiceRow {
      title: "Start screensaver after"
      useDropdown: true
      options: page.choiceFor(page.idleConfig.screensaver)
      value: String(page.idleConfig.screensaver || "")
      dim: page.stayAwake
      onPicked: function(v) { page.setIdle("screensaver", v) }
    }
    CcChoiceRow {
      title: "Lock screen after"
      useDropdown: true
      options: page.choiceFor(page.idleConfig.lock)
      value: String(page.idleConfig.lock || "")
      dim: page.stayAwake
      onPicked: function(v) { page.setIdle("lock", v) }
    }
    CcSwitchRow {
      title: "Show Suspend in the system menu"
      checked: !page.suspendHidden
      onToggled: page.cc.runner.run(["omarchy-toggle-suspend"], function() { page.refreshProfiles() })
    }
  }

  // ------------------------------------------------------------ session
  CcGroup {
    title: "Session"
    subtitle: "Click twice to confirm"
    CcRow {
      icon: Icons.lock; title: "Lock"; clickable: true
      onClicked: { page.cc.launch(["omarchy-system-lock"]) }
    }
    CcRow {
      icon: Icons.sleep; title: page.confirming === "suspend" ? "Click again to suspend" : "Suspend"; clickable: true
      onClicked: page.session("suspend", ["systemctl", "suspend"])
    }
    CcRow {
      icon: Icons.logout; title: page.confirming === "logout" ? "Click again to log out" : "Log out"; clickable: true
      onClicked: page.session("logout", ["omarchy-system", "logout"])
    }
    CcRow {
      icon: Icons.restart; title: page.confirming === "reboot" ? "Click again to restart" : "Restart"; clickable: true
      onClicked: page.session("reboot", ["omarchy-system", "reboot"])
    }
    CcRow {
      icon: Icons.power; title: page.confirming === "shutdown" ? "Click again to shut down" : "Shut down"; clickable: true
      iconColor: Color.urgent
      onClicked: page.session("shutdown", ["omarchy-system", "shutdown"])
    }
  }
}
