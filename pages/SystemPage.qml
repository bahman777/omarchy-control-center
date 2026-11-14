import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// About this computer, updates, date & time, and language.
CcPage {
  id: page

  property var host: ({})
  property var info: ({})
  property string version: ""
  property string updateStatus: ""
  property var time: ({})
  property var zones: []
  property var languages: []
  property string language: ""

  function refresh() {
    cc.runner.run(["hostnamectl", "--json=short"], function(code, out) { try { page.host = JSON.parse(out) } catch (e) {} })
    cc.runner.run(["omarchy-version"], function(code, out) { page.version = String(out).trim() })
    cc.runner.sh(
      "printf 'cpu\\t%s\\n' \"$(lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -1)\";"
      + "printf 'cores\\t%s\\n' \"$(nproc)\";"
      + "printf 'mem\\t%s\\n' \"$(awk '/MemTotal/ {printf \"%.1f GB\", $2/1048576}' /proc/meminfo)\";"
      + "printf 'gpu\\t%s\\n' \"$(lspci 2>/dev/null | sed -n 's/.*\\(VGA\\|3D\\|Display\\)[^:]*: //p' | head -2 | paste -sd ';')\";"
      + "printf 'disk\\t%s\\n' \"$(df -h --output=used,size / | tail -1 | awk '{print $1\" of \"$2\" used\"}')\";"
      + "printf 'uptime\\t%s\\n' \"$(uptime -p | sed 's/^up //')\";"
      + "printf 'wm\\t%s\\n' \"$(hyprctl version -j 2>/dev/null | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get(\"tag\",\"\"))' 2>/dev/null)\"",
      [], function(code, out) {
        var d = {}
        String(out).split("\n").forEach(function(l) { var t = l.split("\t"); if (t.length >= 2) d[t[0]] = t.slice(1).join("\t") })
        page.info = d
      })
    cc.runner.run(["timedatectl", "show"], function(code, out) {
      var d = {}
      String(out).split("\n").forEach(function(l) { var i = l.indexOf("="); if (i > 0) d[l.slice(0, i)] = l.slice(i + 1) })
      page.time = d
    })
    cc.runner.run(["omarchy-language"], function(code, out) { page.language = String(out).trim().split("\n")[0] })
  }
  Component.onCompleted: {
    refresh()
    cc.runner.run(["timedatectl", "list-timezones"], function(code, out) {
      page.zones = String(out).split("\n").filter(function(s) { return /^[A-Za-z0-9_+\-\/]+$/.test(s) })
    })
    cc.runner.run(["omarchy-language", "list"], function(code, out) {
      page.languages = String(out).split("\n").map(function(l) {
        var f = l.split("\t")
        return f.length >= 3 ? { value: f[1], label: f[0] + "  ·  " + f[2] } : null
      }).filter(function(x) { return x !== null })
    })
  }
  Timer { interval: 10000; running: true; repeat: true; onTriggered: page.refresh() }

  CcGroup {
    title: "About"
    CcRow { icon: Icons.laptop; title: "Device"; subtitle: ((page.host.HardwareVendor || "") + " " + (page.host.HardwareModel || "")).trim() || (page.host.Chassis || "—") }
    CcRow { title: "Hostname"; subtitle: page.host.Hostname || "—"; clickable: !!page.host.Hostname; onClicked: page.cc.copy(page.host.Hostname) }
    CcRow { title: "Omarchy"; subtitle: page.version || "—" }
    CcRow { title: "Kernel"; subtitle: page.host.KernelRelease || "—" }
    CcRow { title: "Hyprland"; subtitle: page.info.wm || "—" }
    CcRow { icon: Icons.chip; title: "Processor"; subtitle: (page.info.cpu || "—") + (page.info.cores ? " · " + page.info.cores + " threads" : "") }
    CcRow { icon: Icons.memory; title: "Memory"; subtitle: page.info.mem || "—" }
    CcRow { title: "Graphics"; subtitle: (page.info.gpu || "—").split(";").join("\n") }
    CcRow { icon: Icons.harddisk; title: "Disk"; subtitle: page.info.disk || "—" }
    CcRow { title: "Uptime"; subtitle: page.info.uptime || "—" }
  }

  CcGroup {
    title: "Software updates"
    CcRow {
      icon: Icons.refresh
      title: "Omarchy update"
      subtitle: page.updateStatus || "Check whether a new Omarchy release is out"
      CcButton {
        text: "Check"
        onClicked: {
          page.updateStatus = "Checking…"
          page.cc.runner.run(["omarchy-update-available"], function(code, out) {
            page.updateStatus = String(out).trim() || (code === 0 ? "An update is available" : "Omarchy is up to date")
          })
        }
      }
      CcButton { text: "Update…"; tooltipText: "Runs the update in a terminal"; onClicked: page.cc.launchTerminal("omarchy-update") }
    }
    CcRow {
      title: "Firmware"
      subtitle: "Update device firmware with fwupd"
      clickable: true
      external: true
      onClicked: page.cc.launchTerminal("omarchy-update-firmware")
    }
  }

  CcGroup {
    title: "Date & time"
    CcRow {
      icon: Icons.clock
      title: "Time zone"
      subtitle: page.time.Timezone || ""
      SearchableDropdown {
        width: Style.space(260)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        options: page.zones
        value: page.time.Timezone || ""
        foreground: page.cc.fg
        onChanged: function(v) {
          if (!v || v === page.time.Timezone || page.zones.indexOf(v) < 0) return
          // timedatectl asks polkit, which Omarchy's shell agent answers.
          page.cc.runner.run(["timedatectl", "set-timezone", v], function(code) {
            if (code !== 0) page.cc.toast("Time zone not changed")
            page.refresh()
          })
        }
      }
    }
    CcSwitchRow {
      title: "Automatic time"
      subtitle: page.time.NTPSynchronized === "yes" ? "Synchronized with network time" : "Not synchronized"
      checked: page.time.NTP === "yes"
      onToggled: page.cc.runner.run(["timedatectl", "set-ntp", page.time.NTP === "yes" ? "false" : "true"], function() { page.refresh() })
    }
  }

  CcGroup {
    title: "Language"
    CcRow {
      icon: Icons.translate
      title: "Omarchy language"
      subtitle: "Menus, the shell and Omarchy's own apps"
      SearchableDropdown {
        width: Style.space(260)
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        options: page.languages
        value: page.language
        foreground: page.cc.fg
        onChanged: function(v) {
          // The code ends up inside a Lua string (hyprctl eval) in omarchy-language.
          if (v && v !== page.language && /^[A-Za-z]{2,3}([_-][A-Za-z0-9]{2,4})?(\.[A-Za-z0-9-]{1,10})?(@[A-Za-z]{1,10})?$/.test(v)) page.cc.runner.run(["omarchy-language", v], function() { page.refresh() })
        }
      }
    }
  }
}
