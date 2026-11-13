import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Wired/LAN interfaces, VPN profiles and DNS, from NetworkManager. Refreshes
// whenever `nmcli monitor` reports a change.
CcPage {
  id: page

  property var devices: []      // [{device, type, state, connection}]
  property var addrs: ({})      // iface -> {ipv4:[], ipv6:[], mac, mtu, operstate}
  property var vpns: []         // [{name, type, active}]
  property var routes: ({})     // default gateway per iface
  property string dnsProvider: ""
  property string dnsServers: ""
  property string hostname: ""

  readonly property var wired: devices.filter(function(d) { return d.type === "ethernet" })
  readonly property var others: devices.filter(function(d) {
    return ["ethernet", "wifi", "loopback", "wifi-p2p", "bt"].indexOf(d.type) < 0 && d.device !== "lo"
  })

  function refresh() {
    cc.runner.run(["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"], function(code, out) {
      var list = []
      String(out).split("\n").forEach(function(l) {
        if (!l) return
        var f = l.replace(/\\:/g, "\u0001").split(":").map(function(x) { return x.replace(/\u0001/g, ":") })
        list.push({ device: f[0], type: f[1], state: f[2], connection: f[3] || "" })
      })
      page.devices = list
    })
    cc.runner.run(["ip", "-j", "addr"], function(code, out) {
      var map = {}
      try {
        JSON.parse(out).forEach(function(i) {
          map[i.ifname] = {
            mac: i.address || "", mtu: i.mtu, operstate: i.operstate,
            ipv4: (i.addr_info || []).filter(function(a) { return a.family === "inet" }).map(function(a) { return a.local + "/" + a.prefixlen }),
            ipv6: (i.addr_info || []).filter(function(a) { return a.family === "inet6" && a.scope === "global" }).map(function(a) { return a.local })
          }
        })
      } catch (e) {}
      page.addrs = map
    })
    cc.runner.run(["ip", "-j", "route", "show", "default"], function(code, out) {
      var map = {}
      try { JSON.parse(out).forEach(function(r) { if (!map[r.dev]) map[r.dev] = r.gateway || "" }) } catch (e) {}
      page.routes = map
    })
    cc.runner.run(["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"], function(code, out) {
      var list = []
      String(out).split("\n").forEach(function(l) {
        var f = l.split(":")
        if (f.length < 3) return
        var type = f[f.length - 2], active = f[f.length - 1] === "yes"
        var name = f.slice(0, f.length - 2).join(":").replace(/\\/g, "")
        if (type === "vpn" || type === "wireguard") list.push({ name: name, type: type, active: active })
      })
      page.vpns = list
    })
    cc.runner.run(["omarchy-dns"], function(code, out) { page.dnsProvider = String(out).trim().split("\n")[0] || "" })
    cc.runner.sh("resolvectl dns 2>/dev/null | awk -F': ' 'NF>1 && $2!=\"\" {print $2}' | tr ' ' '\\n' | awk 'NF' | sort -u | head -6 | paste -sd ' '", [], function(code, out) {
      page.dnsServers = String(out).trim()
    })
    cc.runner.run(["hostnamectl", "hostname"], function(code, out) { page.hostname = String(out).trim() })
  }

  Timer { id: refreshSoon; interval: 400; onTriggered: page.refresh() }

  Process {
    running: true
    command: ["nmcli", "monitor"]
    stdout: SplitParser { onRead: function() { refreshSoon.restart() } }
  }

  Component.onCompleted: { refresh(); findVpnFiles() }

  function stateLabel(s) {
    if (s.indexOf("connected") === 0) return "Connected"
    if (s === "unavailable") return "Cable unplugged"
    if (s === "disconnected") return "Disconnected"
    return s.charAt(0).toUpperCase() + s.slice(1)
  }

  CcGroup {
    CcRow {
      icon: Icons.lan
      title: "Devices on this network"
      subtitle: "Everything connected to your LAN: computers, phones, printers, smart-home gear"
      clickable: true
      chevron: true
      onClicked: page.cc.openPage("devices")
    }
  }

  CcGroup {
    title: "Wired"
    subtitle: page.wired.length === 0 ? "No Ethernet adapter. USB and Thunderbolt adapters show up here when plugged in." : ""
    Repeater {
      model: page.wired
      delegate: Column {
        id: wd
        required property var modelData
        readonly property var info: page.addrs[modelData.device] || {}
        readonly property bool up: modelData.state.indexOf("connected") === 0
        width: parent ? parent.width : 0
        CcSwitchRow {
          icon: Icons.ethernet
          title: wd.modelData.connection || wd.modelData.device
          subtitle: page.stateLabel(wd.modelData.state) + (wd.info.ipv4 && wd.info.ipv4.length ? " · " + wd.info.ipv4.join(", ") : "")
          checked: wd.up
          busy: wd.modelData.state.indexOf("ing") > 0
          onToggled: page.cc.runner.run(["nmcli", "device", wd.up ? "disconnect" : "connect", wd.modelData.device], function() { refreshSoon.restart() })
        }
        CcRow { visible: wd.up; title: "Gateway"; subtitle: page.routes[wd.modelData.device] || "—" }
        CcRow { visible: wd.up && !!wd.info.ipv6 && wd.info.ipv6.length > 0; title: "IPv6"; subtitle: (wd.info.ipv6 || []).join(", ") }
        CcRow { title: "Hardware address"; subtitle: (wd.info.mac || "—") + (wd.info.mtu ? " · MTU " + wd.info.mtu : "") }
      }
    }
  }

  CcSpeedTest {}

  CcGroup {
    title: "VPN"
    subtitle: page.vpns.length === 0 ? "No VPN profiles in NetworkManager. Tailscale has its own page." : ""
    header: [ CcButton { text: "Set up manually…"; tooltipText: "Opens nmtui in a terminal"; onClicked: page.cc.launchTerminal("nmtui edit") } ]
    Repeater {
      model: page.vpns
      delegate: CcSwitchRow {
        required property var modelData
        icon: Icons.vpn
        title: modelData.name
        subtitle: (modelData.type === "wireguard" ? "WireGuard" : "VPN") + (modelData.active ? " · Connected" : "")
        checked: modelData.active
        onToggled: page.cc.runner.run(["nmcli", "connection", modelData.active ? "down" : "up", "id", modelData.name], function(code) {
          if (code !== 0) page.cc.toast("Could not change " + modelData.name)
          refreshSoon.restart()
        })
      }
    }
  }

  // ------------------------------------------------------------ VPN import
  // WireGuard (.conf) and OpenVPN (.ovpn) files from Downloads, Documents and
  // home, or any path, imported with NetworkManager. A WireGuard file's name
  // becomes the interface name (15 characters max), so a longer one is
  // copied under a short name to the private runtime folder and removed
  // right after the import: the file holds a private key.
  property var vpnFiles: []           // [{ type, path, name }]
  property bool openvpnSupport: true
  property bool importing: false
  function findVpnFiles() {
    page.cc.runner.run(["sh", "-c",
      "test -e /usr/lib/NetworkManager/VPN/nm-openvpn-service.name && echo has-openvpn; " +
      "find \"$HOME/Downloads\" \"$HOME/Documents\" \"$HOME\" -maxdepth 2 -type f \\( -iname '*.ovpn' -o -iname '*.conf' \\) -size -64k 2>/dev/null | " +
      "while IFS= read -r f; do case \"$f\" in *.ovpn|*.OVPN) echo \"openvpn|$f\";; *) grep -qs '^\\[Interface\\]' \"$f\" && grep -qs 'PrivateKey' \"$f\" && echo \"wireguard|$f\";; esac; done | sort -u | head -20"],
      function(code, out) {
        var lines = String(out).split("\n")
        page.openvpnSupport = lines.indexOf("has-openvpn") >= 0
        page.vpnFiles = lines.filter(function(l) { return l.indexOf("|") > 0 }).map(function(l) {
          var i = l.indexOf("|"), path = l.slice(i + 1)
          return { type: l.slice(0, i), path: path, name: path.replace(/^.*\//, "") }
        })
      })
  }
  function vpnType(path) { return /\.ovpn$/i.test(path) ? "openvpn" : "wireguard" }
  function importVpn(path) {
    path = String(path || "").trim().replace(/^~(?=\/)/, Quickshell.env("HOME"))
    if (!path || path.indexOf("/") !== 0) { page.cc.toast("Enter the full path to the file"); return }
    var type = vpnType(path)
    if (type === "openvpn" && !page.openvpnSupport) { page.cc.toast("Install OpenVPN support first"); return }
    importing = true
    var script = type === "wireguard"
      ? "f=\"$1\"; b=$(basename \"$f\" .conf); n=$(printf '%s' \"$b\" | tr -c 'A-Za-z0-9_-' '_' | cut -c1-15); " +
        "if [ \"$n\" != \"$b\" ]; then d=\"${XDG_RUNTIME_DIR:-/tmp}/cc-vpn\"; umask 077; mkdir -p \"$d\"; cp \"$f\" \"$d/$n.conf\" || exit 1; " +
        "nmcli connection import type wireguard file \"$d/$n.conf\"; r=$?; rm -f \"$d/$n.conf\"; exit $r; fi; " +
        "nmcli connection import type wireguard file \"$f\""
      : "nmcli connection import type openvpn file \"$1\""
    page.cc.runner.run(["sh", "-c", script, "sh", path], function(code, out) {
      page.importing = false
      if (code === 0) { page.cc.toast("VPN added"); vpnPath.text = ""; refreshSoon.restart() }
      else page.cc.toast("Couldn't import that file")
    })
  }

  CcGroup {
    title: "Import a VPN"
    subtitle: page.vpnFiles.length ? "Found in Downloads, Documents and your home folder" : "WireGuard (.conf) or OpenVPN (.ovpn) files from your VPN provider"
    header: [ CcButton { text: "Look again"; onClicked: page.findVpnFiles() } ]
    CcRow {
      visible: !page.openvpnSupport && page.vpnFiles.some(function(f) { return f.type === "openvpn" })
      icon: Icons.info
      title: "OpenVPN support isn't installed"
      subtitle: "WireGuard works without it"
      CcButton { text: "Install"; onClicked: page.cc.launchTerminal("omarchy-pkg-add networkmanager-openvpn") }
    }
    Repeater {
      model: page.vpnFiles
      delegate: CcRow {
        required property var modelData
        icon: Icons.vpn
        title: modelData.name
        subtitle: (modelData.type === "wireguard" ? "WireGuard" : "OpenVPN") + " · " + modelData.path.replace(Quickshell.env("HOME"), "~").replace(/\/[^\/]*$/, "")
        CcButton { text: "Import"; enabled: !page.importing && (modelData.type === "wireguard" || page.openvpnSupport); onClicked: page.importVpn(modelData.path) }
      }
    }
    CcRow {
      title: "Another file"
      subtitle: "Full path to a .conf or .ovpn file"
      TextField {
        id: vpnPath
        width: Style.space(220)
        placeholderText: "~/vpn/home.conf"
        onAccepted: page.importVpn(text)
      }
      CcButton { text: "Import"; enabled: !page.importing && vpnPath.text.trim() !== ""; onClicked: page.importVpn(vpnPath.text) }
    }
  }

  CcGroup {
    title: "Other interfaces"
    visible: page.others.length > 0
    Repeater {
      model: page.others
      delegate: CcRow {
        required property var modelData
        readonly property var info: page.addrs[modelData.device] || {}
        icon: modelData.device.indexOf("tailscale") === 0 ? Icons.vpn : (modelData.type === "bridge" ? Icons.lan : Icons.server)
        title: modelData.device
        subtitle: modelData.type + " · " + page.stateLabel(modelData.state) + (info.ipv4 && info.ipv4.length ? " · " + info.ipv4.join(", ") : "")
        clickable: !!(info.ipv4 && info.ipv4.length)
        onClicked: page.cc.copy(String(info.ipv4[0]).split("/")[0])
      }
    }
  }

  CcGroup {
    title: "DNS"
    CcChoiceRow {
      icon: Icons.web
      title: "Provider"
      subtitle: page.dnsServers !== "" ? "Using " + page.dnsServers : ""
      options: [{ value: "DHCP", label: "Automatic" }, { value: "Cloudflare", label: "Cloudflare" }, { value: "Google", label: "Google" }]
      value: page.dnsProvider
      onPicked: function(v) {
        // omarchy-dns elevates itself (sudoers rule or polkit).
        page.cc.runner.run(["omarchy-dns", v], function(code) {
          if (code !== 0) page.cc.toast("Could not switch DNS")
          refreshSoon.restart()
        })
      }
    }
    CcRow {
      id: customDns
      title: "Custom DNS servers"
      subtitle: "Space-separated, e.g. 192.168.1.1 1.1.1.1"
      readonly property bool valid: /^[0-9A-Fa-f:.,\s]+$/.test(dnsField.text) && dnsField.text.trim().length >= 7
      TextField {
        id: dnsField
        width: Style.space(220)
        placeholderText: page.dnsProvider === "Custom" ? page.dnsServers : "1.1.1.1 9.9.9.9"
        foreground: page.cc.fg
        Keys.onReturnPressed: applyDns.clicked()
        property bool ccFocusable: visible
        property bool hasCursor: false
        function ccActivate() { forceActiveFocus() }
      }
      CcButton {
        id: applyDns
        text: "Apply"
        onClicked: {
          if (!customDns.valid) { page.cc.toast("Enter IP addresses only"); return }
          // omarchy-dns reads the list on stdin and elevates itself.
          page.cc.runner.runWithInput(["omarchy-dns", "Custom"], dnsField.text.trim() + "\n", function(code) {
            page.cc.toast(code === 0 ? "Custom DNS set" : "Could not set custom DNS")
            dnsField.text = ""
            refreshSoon.restart()
          })
        }
      }
    }
  }

  CcGroup {
    title: "This computer"
    CcRow { icon: Icons.laptop; title: "Hostname"; subtitle: page.hostname || "—"; clickable: page.hostname !== ""; onClicked: page.cc.copy(page.hostname) }
    CcRow {
      icon: Icons.cog
      title: "Advanced connection editor"
      subtitle: "Static IPs, proxies, bonds and bridges in nmtui"
      clickable: true
      external: true
      tip: "Opens nmtui in a terminal"
      onClicked: page.cc.launchTerminal("nmtui")
    }
  }
}
