import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Tailscale status, preferences, exit node and machines. Polls the local
// daemon while the page is open.
CcPage {
  id: page

  property bool installed: true
  property bool loaded: false
  property var status: ({})
  property var prefs: ({})
  property bool busy: false
  property string filter: ""

  readonly property string backend: status.BackendState || ""
  readonly property bool running: backend === "Running"
  readonly property var self: status.Self || {}
  readonly property var peers: {
    var p = status.Peer || {}
    var list = Object.keys(p).map(function(k) {
      var x = p[k]
      return {
        host: String(x.HostName || ""), dns: String(x.DNSName || "").replace(/\.$/, ""),
        os: String(x.OS || ""), ip: (x.TailscaleIPs || [])[0] || "", online: !!x.Online,
        exitOption: !!x.ExitNodeOption, exitActive: !!x.ExitNode, id: String(x.ID || ""),
        relay: String(x.Relay || ""), direct: !!x.CurAddr, lastSeen: String(x.LastSeen || "")
      }
    })
    list.sort(function(a, b) {
      if (a.online !== b.online) return a.online ? -1 : 1
      return a.host.localeCompare(b.host)
    })
    return list
  }
  readonly property var exitNodes: peers.filter(function(p) { return p.exitOption })
  readonly property string exitNodeIp: prefs.ExitNodeIP || ""
  readonly property string currentExit: {
    for (var i = 0; i < peers.length; i++) if (peers[i].exitActive) return peers[i].ip
    return exitNodeIp
  }

  function refresh() {
    cc.runner.run(["tailscale", "status", "--json"], function(code, out) {
      if (code === 127 || (code !== 0 && String(out).trim() === "")) { page.installed = code !== 127; page.loaded = true; return }
      try { page.status = JSON.parse(out) } catch (e) {}
      page.loaded = true
    })
    cc.runner.run(["tailscale", "debug", "prefs"], function(code, out) {
      try { page.prefs = JSON.parse(out) } catch (e) {}
    })
  }

  function tsSet(flag, value) {
    busy = true
    cc.runner.run(["tailscale", "set", "--" + flag + "=" + value], function(code) {
      page.busy = false
      if (code !== 0) page.cc.toast("Tailscale refused the change — try: sudo tailscale set --operator=$USER")
      page.refresh()
    })
  }

  function toggle() {
    busy = true
    var argv = running ? ["tailscale", "down"] : ["tailscale", "up"]
    if (!running && (backend === "NeedsLogin" || backend === "NoState")) {
      // Login needs a browser round-trip; Omarchy's own Tailscale panel does that well.
      page.cc.summon("omarchy.tailscale", "")
      busy = false
      return
    }
    cc.runner.run(argv, function(code) {
      page.busy = false
      if (code !== 0) page.cc.toast("Tailscale needs operator rights: sudo tailscale set --operator=$USER")
      page.refresh()
    })
  }

  Timer { interval: 4000; running: true; repeat: true; triggeredOnStart: true; onTriggered: page.refresh() }

  CcGroup {
    visible: !page.installed
    CcRow {
      icon: Icons.vpn
      title: "Tailscale is not installed"
      subtitle: "Install the mesh VPN service and its admin console web app"
      CcButton { text: "Install"; tooltipText: "Installs Tailscale in a terminal"; onClicked: page.cc.launchTerminal("omarchy-install-service-tailscale") }
    }
  }

  CcGroup {
    visible: page.installed
    CcSwitchRow {
      icon: Icons.vpn
      title: "Tailscale"
      subtitle: !page.loaded ? "Checking…"
        : page.running ? "Connected to " + ((page.status.CurrentTailnet || {}).Name || "your tailnet")
        : page.backend === "NeedsLogin" ? "Signed out — click to sign in"
        : page.backend === "Stopped" ? "Disconnected" : page.backend
      checked: page.running
      busy: page.busy
      onToggled: page.toggle()
    }
    CcRow {
      visible: page.running
      title: "This machine"
      subtitle: (page.self.HostName || "") + " · " + (page.self.TailscaleIPs || []).join(", ")
      clickable: true
      onClicked: page.cc.copy((page.self.TailscaleIPs || [""])[0])
      CcText { text: "Copy IP"; color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62); font.pixelSize: Style.font.caption }
    }
    CcRow {
      visible: page.running && !!page.self.DNSName
      title: "MagicDNS name"
      subtitle: String(page.self.DNSName || "").replace(/\.$/, "")
      clickable: true
      onClicked: page.cc.copy(String(page.self.DNSName || "").replace(/\.$/, ""))
    }
    Repeater {
      model: page.running ? (page.status.Health || []) : []
      delegate: CcRow {
        required property var modelData
        icon: Icons.info
        iconColor: Color.urgent
        title: "Health warning"
        subtitle: String(modelData)
      }
    }
  }

  CcGroup {
    visible: page.running
    title: "Exit node"
    subtitle: "Route all your internet traffic through another machine on your tailnet"
    CcChoiceRow {
      icon: Icons.web
      title: "Use exit node"
      useDropdown: true
      dropdownWidth: Style.space(260)
      options: [{ value: "", label: "None" }].concat(page.exitNodes.map(function(p) {
        return { value: p.ip, label: p.host + (p.online ? "" : " (offline)") }
      }))
      value: page.currentExit
      onPicked: function(v) { page.tsSet("exit-node", v) }
    }
    CcSwitchRow {
      title: "Allow local network access"
      subtitle: "Keep reaching printers and devices on your LAN while using an exit node"
      checked: !!page.prefs.ExitNodeAllowLANAccess
      busy: page.busy
      onToggled: page.tsSet("exit-node-allow-lan-access", !page.prefs.ExitNodeAllowLANAccess)
    }
  }

  CcGroup {
    visible: page.running
    title: "Preferences"
    CcSwitchRow {
      title: "Use Tailscale DNS"
      subtitle: "MagicDNS names and your tailnet's DNS settings"
      checked: !!page.prefs.CorpDNS
      busy: page.busy
      onToggled: page.tsSet("accept-dns", !page.prefs.CorpDNS)
    }
    CcSwitchRow {
      title: "Accept subnet routes"
      subtitle: "Reach networks other machines advertise"
      checked: !!page.prefs.RouteAll
      busy: page.busy
      onToggled: page.tsSet("accept-routes", !page.prefs.RouteAll)
    }
    CcSwitchRow {
      title: "Block incoming connections"
      subtitle: "Shields up: other machines can't connect to this one"
      checked: !!page.prefs.ShieldsUp
      busy: page.busy
      onToggled: page.tsSet("shields-up", !page.prefs.ShieldsUp)
    }
    CcSwitchRow {
      title: "Tailscale SSH"
      subtitle: "Let tailnet members SSH in, per your ACLs"
      checked: !!page.prefs.RunSSH
      busy: page.busy
      onToggled: page.tsSet("ssh", !page.prefs.RunSSH)
    }
  }

  CcGroup {
    visible: page.running
    title: "Machines"
    subtitle: page.peers.filter(function(p) { return p.online }).length + " of " + page.peers.length + " online · click to copy the IP, right-click to send files"
    header: [ CcButton { text: "Admin console"; tooltipText: "Opens the Tailscale admin console in your browser"; onClicked: page.cc.launch(["omarchy-launch-browser", "https://login.tailscale.com/admin/machines"]) } ]
    Repeater {
      model: page.peers
      delegate: CcRow {
        required property var modelData
        icon: modelData.os === "iOS" || modelData.os === "android" ? Icons.phone : (modelData.os === "linux" && modelData.host.indexOf("server") >= 0 ? Icons.server : Icons.laptop)
        iconColor: modelData.online ? Color.menu.text : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.4)
        title: modelData.host + (modelData.exitActive ? "  · exit node" : "")
        subtitle: modelData.ip + " · " + modelData.os + (modelData.online ? (modelData.direct ? " · direct" : (modelData.relay ? " · relay " + modelData.relay : "")) : " · offline")
        dim: !modelData.online
        clickable: true
        onClicked: page.cc.copy(modelData.ip)
        onRightClicked: page.cc.launch(["omarchy-tailscale-send", modelData.host])
        Rectangle {
          width: Style.space(8); height: width; radius: width / 2
          color: modelData.online ? "#3fb950" : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.3)
        }
      }
    }
  }
}
