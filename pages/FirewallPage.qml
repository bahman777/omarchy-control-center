import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Firewall (ufw): on/off, what gets in by default, and the rules that let
// things in. State and rules are read from ufw's own files, which anyone can
// read, so opening the page asks for nothing; every change goes through
// pkexec (the system's password prompt).
CcPage {
  id: page

  property bool installed: true
  property bool enabled: false
  property string inPolicy: ""      // DROP / REJECT / ACCEPT
  property var rules: []            // [{action, proto, port, from, to, iface, comment, families}]
  property var lans: []             // ["192.168.1.0/24", ...]
  property bool busy: false

  function hex2str(h) {
    var out = ""
    for (var i = 0; i + 1 < h.length; i += 2) out += String.fromCharCode(parseInt(h.substr(i, 2), 16))
    return out
  }
  function anyAddr(a) { return a === "0.0.0.0/0" || a === "::/0" || a === "any" }

  // "### tuple ### allow tcp 22 0.0.0.0/0 any 192.168.1.0/24 in comment=6d44"
  // action proto dport dst sport src [dapp sapp] direction[_iface] [comment=hex]
  function parse(text, family) {
    var list = []
    String(text).split("\n").forEach(function(line) {
      if (line.indexOf("### tuple ### ") !== 0) return
      var t = line.slice(14).trim().split(/\s+/)
      var comment = ""
      t = t.filter(function(x) { if (x.indexOf("comment=") === 0) { comment = page.hex2str(x.slice(8)); return false } return true })
      if (t.length < 7) return
      var dir = t[t.length - 1], iface = ""
      var u = dir.indexOf("_")
      if (u > 0) { iface = dir.slice(u + 1); dir = dir.slice(0, u) }
      if (dir !== "in") return
      list.push({ action: t[0], proto: t[1], port: t[2], to: page.anyAddr(t[3]) ? "any" : t[3],
                  sport: t[4], from: page.anyAddr(t[5]) ? "any" : t[5], iface: iface, comment: comment, family: family })
    })
    return list
  }

  function refresh() {
    cc.runner.run(["sh", "-c", "command -v ufw >/dev/null || exit 3; grep -E '^ENABLED=' /etc/ufw/ufw.conf; grep -E '^DEFAULT_INPUT_POLICY=' /etc/default/ufw; echo '@@4'; cat /etc/ufw/user.rules; echo '@@6'; cat /etc/ufw/user6.rules"], function(code, out) {
      if (code === 3) { page.installed = false; return }
      page.installed = true
      var s = String(out)
      page.enabled = /ENABLED=yes/.test(s)
      var m = s.match(/DEFAULT_INPUT_POLICY="?([A-Z]+)/)
      page.inPolicy = m ? m[1] : ""
      var i4 = s.indexOf("@@4"), i6 = s.indexOf("@@6")
      var all = page.parse(s.slice(i4, i6), "4").concat(page.parse(s.slice(i6), "6"))
      // One row for a rule that exists for both IPv4 and IPv6 ("any").
      var merged = [], seen = {}
      all.forEach(function(r) {
        var key = [r.action, r.proto, r.port, r.from, r.to, r.sport, r.iface].join("|")
        if (seen[key]) { if (seen[key].families.indexOf(r.family) < 0) seen[key].families.push(r.family); return }
        r.families = [r.family]; seen[key] = r; merged.push(r)
      })
      page.rules = merged
    })
    cc.runner.run(["ip", "-o", "-f", "inet", "addr", "show", "scope", "global"], function(code, out) {
      var nets = []
      String(out).split("\n").forEach(function(l) {
        var f = l.trim().split(/\s+/)
        if (f.length < 4 || /^(lo|docker|br-|veth|tailscale|virbr)/.test(f[1])) return
        var c = f[3].split("/"), ip = c[0].split(".").map(Number), bits = Number(c[1])
        if (ip.length !== 4 || !(bits >= 8 && bits <= 30)) return
        var n = ((ip[0] << 24) >>> 0) + (ip[1] << 16) + (ip[2] << 8) + ip[3]
        var mask = bits === 0 ? 0 : (0xFFFFFFFF << (32 - bits)) >>> 0
        var net = (n & mask) >>> 0
        var s = [net >>> 24, (net >>> 16) & 255, (net >>> 8) & 255, net & 255].join(".") + "/" + bits
        if (nets.indexOf(s) < 0) nets.push(s)
      })
      page.lans = nets
    })
  }
  Component.onCompleted: refresh()
  Timer { interval: 5000; running: true; repeat: true; onTriggered: if (!page.busy) page.refresh() }

  // Runs `pkexec ufw <args>` one after another; refreshes at the end.
  function ufw(argLists, okText) {
    busy = true
    var i = 0
    function next() {
      if (i >= argLists.length) { page.busy = false; if (okText) page.cc.toast(okText); page.refresh(); return }
      page.cc.runner.run(["pkexec", "ufw"].concat(argLists[i++]), function(code, out) {
        if (code !== 0) { page.busy = false; page.cc.toast(code === 126 || code === 127 ? "Cancelled" : "The firewall didn't accept that"); page.refresh(); return }
        next()
      })
    }
    next()
  }

  // A rule back into ufw's own syntax (for deleting it).
  function spec(r) {
    var a = [r.action, "in"]
    if (r.iface) a = a.concat(["on", r.iface])
    if (r.proto !== "any") a = a.concat(["proto", r.proto])
    a = a.concat(["from", r.from])
    if (r.sport !== "any") a = a.concat(["port", r.sport])
    a = a.concat(["to", r.to])
    if (r.port !== "any") a = a.concat(["port", r.port])
    return a
  }
  function ruleTitle(r) {
    var what = r.port === "any" ? "Everything" : "Port " + r.port.replace(":", "–")
    var proto = r.proto === "any" ? "" : " " + r.proto.toUpperCase()
    var verb = r.action === "allow" ? "" : r.action === "limit" ? " (rate-limited)" : " (" + r.action + ")"
    return what + proto + verb
  }
  function ruleSubtitle(r) {
    var parts = []
    parts.push(r.iface ? "on " + r.iface : r.from === "any" ? "from anywhere" : "from " + r.from)
    if (r.iface && r.from !== "any") parts.push("from " + r.from)
    if (r.to !== "any") parts.push("to " + r.to)
    if (r.families.length === 1) parts.push(r.families[0] === "4" ? "IPv4 only" : "IPv6 only")
    if (r.comment) parts.push(r.comment)
    return parts.join(" · ")
  }

  // ------------------------------------------------------------ add a rule
  property string newProto: "tcp"
  property string newFrom: "lan"
  readonly property string portText: portField.text.trim()
  readonly property bool portValid: {
    var m = portText.match(/^(\d{1,5})(?:[:-](\d{1,5}))?$/)
    if (!m) return false
    var a = Number(m[1]), b = m[2] ? Number(m[2]) : a
    return a >= 1 && b <= 65535 && a <= b
  }
  function addRule() {
    if (!portValid) return
    var port = portText.replace("-", ":")
    var range = port.indexOf(":") > 0
    var protos = newProto === "both" ? (range ? ["tcp", "udp"] : [""]) : [newProto]
    var froms = newFrom === "lan" && lans.length ? lans : ["any"]
    var lists = []
    protos.forEach(function(p) {
      froms.forEach(function(f) {
        var a = ["allow", "in"]
        if (p) a = a.concat(["proto", p])
        lists.push(a.concat(["from", f, "to", "any", "port", port]))
      })
    })
    ufw(lists, "Port " + portText + " is open")
    portField.text = ""
  }

  CcGroup {
    visible: !page.installed
    title: "Firewall"
    CcRow {
      icon: Icons.firewall
      title: "The ufw firewall isn't installed"
      subtitle: "Install it to block unwanted connections to this computer"
      CcButton { text: "Install"; onClicked: page.cc.launchTerminal("omarchy-pkg-add ufw && sudo ufw default deny incoming && sudo ufw --force enable && sudo systemctl enable --now ufw") }
    }
  }

  CcGroup {
    visible: page.installed
    title: "Firewall"
    CcSwitchRow {
      icon: Icons.firewall
      title: page.enabled ? "On" : "Off"
      subtitle: page.enabled ? "Blocking connections you haven't allowed" : "Every connection to this computer is allowed"
      checked: page.enabled
      busy: page.busy
      onToggled: page.ufw([page.enabled ? ["disable"] : ["--force", "enable"]], page.enabled ? "Firewall off" : "Firewall on")
    }
    CcChoiceRow {
      title: "Incoming connections"
      subtitle: "What happens to a connection no rule below allows"
      options: [{ value: "DROP", label: "Block" }, { value: "REJECT", label: "Refuse" }, { value: "ACCEPT", label: "Allow" }]
      value: page.inPolicy
      onPicked: function(v) { page.ufw([["default", v === "DROP" ? "deny" : v === "REJECT" ? "reject" : "allow", "incoming"]], "Saved") }
    }
  }

  CcGroup {
    visible: page.installed
    title: "Allowed in"
    subtitle: page.rules.length ? "" : "Nothing is allowed in beyond replies to your own connections."
    Repeater {
      model: page.rules
      delegate: CcRow {
        required property var modelData
        icon: modelData.iface ? Icons.vpn : modelData.from === "any" ? Icons.web : Icons.lan
        title: page.ruleTitle(modelData)
        subtitle: page.ruleSubtitle(modelData)
        CcButton {
          text: "Remove"
          tooltipText: "Close this again (asks for your password)"
          onClicked: page.ufw([["delete"].concat(page.spec(modelData))], "Removed")
        }
      }
    }
  }

  CcGroup {
    visible: page.installed
    title: "Open a port"
    subtitle: "For an app that other devices connect to, such as a game or a media server"
    CcRow {
      title: "Port"
      subtitle: "A number, or a range like 6000-6010"
      TextField {
        id: portField
        width: Style.space(150)
        placeholderText: "e.g. 8080"
        inputMethodHints: Qt.ImhPreferNumbers
        onAccepted: page.addRule()
      }
    }
    CcChoiceRow {
      title: "Protocol"
      options: [{ value: "tcp", label: "TCP" }, { value: "udp", label: "UDP" }, { value: "both", label: "Both" }]
      value: page.newProto
      onPicked: function(v) { page.newProto = v }
    }
    CcChoiceRow {
      title: "From"
      subtitle: page.newFrom === "lan" ? (page.lans.length ? page.lans.join(", ") : "No local network right now: anywhere") : "Any address, including the internet"
      options: [{ value: "lan", label: "Local network" }, { value: "any", label: "Anywhere" }]
      value: page.newFrom
      onPicked: function(v) { page.newFrom = v }
    }
    CcRow {
      title: page.portValid ? "Allow port " + page.portText + (page.newProto === "both" ? "" : " " + page.newProto.toUpperCase()) : "Enter a port to open"
      CcButton { text: "Open port"; enabled: page.portValid && !page.busy; onClicked: page.addRule() }
    }
  }
}
