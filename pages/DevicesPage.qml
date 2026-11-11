import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Everything on the local network: a ping sweep of the subnet fills the
// neighbour table, then names come from mDNS and DNS, vendors from the MAC
// registry, and services from mDNS adverts.
CcPage {
  id: page

  property var devices: []
  property bool scanning: false
  property string subnet: ""
  property string self: ""
  property string gateway: ""
  property string lastScan: ""
  property string filter: ""

  // Helper run by bash with values as arguments, never spliced into code.
  readonly property string scanScript: '
    iface=$(ip -j route show default | python3 -I -c "import json,sys; r=json.load(sys.stdin); print(r[0][\\"dev\\"] if r else \\"\\")")
    [ -n "$iface" ] || exit 3
    gw=$(ip -j route show default dev "$iface" | python3 -I -c "import json,sys; r=json.load(sys.stdin); print(r[0].get(\\"gateway\\",\\"\\") if r else \\"\\")")
    cidr=$(ip -j -4 addr show dev "$iface" | python3 -I -c "import json,sys; a=json.load(sys.stdin)[0][\\"addr_info\\"][0]; print(a[\\"local\\"]+\\"/\\"+str(a[\\"prefixlen\\"]))")
    echo "self	${cidr%/*}"; echo "subnet	$cidr"; echo "gateway	$gw"
    # Ping sweep only for home-sized subnets (/22 or smaller).
    python3 -I -c "import ipaddress,sys
n=ipaddress.ip_network(sys.argv[1],strict=False)
if n.prefixlen>=22: print(chr(10).join(str(h) for h in n.hosts()))" "$cidr" | xargs -r -P 96 -I{} ping -c1 -W1 -q {} >/dev/null 2>&1
    ip -j neigh show dev "$iface" | python3 -I -c "import json,sys
for e in json.load(sys.stdin):
  if e.get(\\"lladdr\\") and \\":\\" not in e.get(\\"dst\\",\\":\\") and e.get(\\"state\\",[\\"\\"])[0] not in (\\"FAILED\\",\\"INCOMPLETE\\"): print(\\"neigh\\t\\"+e[\\"dst\\"]+\\"\\t\\"+e[\\"lladdr\\"])"
    timeout 6 avahi-browse -arpt 2>/dev/null | awk -F";" "\\$1==\\"=\\" && \\$3==\\"IPv4\\" {print \\"mdns\\t\\" \\$8 \\"\\t\\" \\$7 \\"\\t\\" \\$5 \\"\\t\\" \\$4}"
  '
  readonly property string resolveScript: '
    oui=/usr/share/hwdata/oui.txt
    for a in "$@"; do
      ip=${a%%,*}; mac=${a#*,}
      name=$(getent hosts "$ip" | awk "{print \\$2; exit}")
      pre=$(echo "$mac" | cut -c1-8 | tr ":" "-" | tr a-f A-F)
      vendor=""
      [ -r "$oui" ] && vendor=$(grep -m1 "^$pre" "$oui" | cut -f3-)
      printf "%s\\t%s\\t%s\\n" "$ip" "$name" "$vendor"
    done
  '

  function serviceLabel(t) {
    var map = { "_ipp._tcp": "Printer", "_ipps._tcp": "Printer", "_printer._tcp": "Printer", "_pdl-datastream._tcp": "Printer",
      "_uscan._tcp": "Scanner", "_uscans._tcp": "Scanner", "_airplay._tcp": "AirPlay", "_raop._tcp": "AirPlay",
      "_googlecast._tcp": "Chromecast", "_spotify-connect._tcp": "Spotify", "_ssh._tcp": "SSH", "_sftp-ssh._tcp": "SSH",
      "_smb._tcp": "File sharing", "_afpovertcp._tcp": "File sharing", "_hap._tcp": "HomeKit", "_homekit._tcp": "HomeKit",
      "_companion-link._tcp": "Apple device", "_http._tcp": "Web", "_https._tcp": "Web", "_workstation._tcp": "Computer",
      "_sonos._tcp": "Sonos", "_matter._tcp": "Matter", "_rdlink._tcp": "Apple device", "_device-info._tcp": "" }
    if (map[t] !== undefined) return map[t]
    var m = /^Internet Printer$|Printer/.exec(t)
    return m ? "Printer" : ""
  }
  function kindIcon(d) {
    var s = d.services.join(" ") + " " + d.vendor + " " + d.name
    if (d.ip === gateway) return Icons.web
    if (/Printer/.test(s)) return Icons.printer
    if (/Scanner/.test(s)) return String.fromCodePoint(0xF06AB)
    if (/Chromecast|AirPlay|Sonos|Spotify/.test(s)) return Icons.speaker
    if (/iPhone|Pixel|Galaxy|android/i.test(s)) return Icons.phone
    if (/Apple|MacBook|Computer|SSH|File sharing/i.test(s)) return Icons.laptop
    return Icons.lan
  }

  function scan() {
    if (scanning) return
    scanning = true
    cc.runner.sh(scanScript, [], function(code, out) {
      var neigh = {}, mdns = {}
      String(out).split("\n").forEach(function(l) {
        var f = l.split("\t")
        if (f[0] === "self") page.self = f[1] || ""
        else if (f[0] === "subnet") page.subnet = f[1] || ""
        else if (f[0] === "gateway") page.gateway = f[1] || ""
        else if (f[0] === "neigh" && /^[0-9.]+$/.test(f[1]) && /^[0-9a-f:]{17}$/i.test(f[2])) neigh[f[1]] = f[2].toLowerCase()
        else if (f[0] === "mdns" && /^[0-9.]+$/.test(f[1])) {
          var e = mdns[f[1]] || (mdns[f[1]] = { host: "", services: [] })
          if (!e.host && f[2]) e.host = String(f[2]).replace(/\.local$/, "")
          var lab = page.serviceLabel(f[3])
          if (lab && e.services.indexOf(lab) < 0) e.services.push(lab)
        }
      })
      var ips = Object.keys(neigh).filter(function(ip) { return ip !== page.self })
      if (ips.length === 0) { page.devices = []; page.scanning = false; return }
      page.cc.runner.sh(page.resolveScript, ips.map(function(ip) { return ip + "," + neigh[ip] }), function(c2, o2) {
        var info = {}
        String(o2).split("\n").forEach(function(l) { var f = l.split("\t"); if (f.length >= 3) info[f[0]] = { dns: f[1], vendor: f[2] } })
        var list = ips.map(function(ip) {
          var mac = neigh[ip], m = mdns[ip] || { host: "", services: [] }, inf = info[ip] || { dns: "", vendor: "" }
          // A locally administered MAC (phones' private Wi-Fi address) has no vendor.
          var priv = /^.[26ae]/.test(mac)
          return {
            ip: ip, mac: mac,
            name: String(m.host || (inf.dns && inf.dns !== ip ? inf.dns.replace(/\.(lan|local|home)$/, "") : "")).slice(0, 60),
            vendor: priv ? "Private address" : String(inf.vendor || "").trim().slice(0, 50),
            services: m.services
          }
        })
        list.sort(function(a, b) {
          var pa = a.ip.split(".").map(Number), pb = b.ip.split(".").map(Number)
          for (var i = 0; i < 4; i++) if (pa[i] !== pb[i]) return pa[i] - pb[i]
          return 0
        })
        page.devices = list
        page.lastScan = Qt.formatTime(new Date(), "h:mm AP")
        page.scanning = false
      })
    })
  }
  Component.onCompleted: scan()

  readonly property var shown: devices.filter(function(d) {
    var q = filter.trim().toLowerCase()
    return q === "" || (d.ip + " " + d.name + " " + d.vendor + " " + d.mac + " " + d.services.join(" ")).toLowerCase().indexOf(q) >= 0
  })

  CcGroup {
    title: scanning ? "Scanning " + (page.subnet || "your network") + "…" : page.devices.length + " devices on " + (page.subnet || "this network")
    subtitle: page.lastScan ? "Last scan " + page.lastScan + " · click a device to copy its IP" : "Pings every address on your subnet, then reads names and services"
    header: [ CcButton { text: page.scanning ? "Scanning…" : "Scan again"; onClicked: page.scan() } ]
    CcRow {
      title: "Filter"
      TextField {
        width: Style.space(220)
        placeholderText: "Name, IP, vendor or service"
        foreground: page.cc.fg
        onTextChanged: page.filter = text
        property bool ccFocusable: visible
        property bool hasCursor: false
        function ccActivate() { forceActiveFocus() }
      }
    }
    CcRow {
      visible: page.self !== ""
      icon: Icons.laptop
      iconColor: page.cc.accent
      title: "This computer"
      subtitle: page.self
    }
    Repeater {
      model: page.shown
      delegate: CcRow {
        required property var modelData
        icon: page.kindIcon(modelData)
        title: (modelData.ip === page.gateway ? "Router" + (modelData.name ? " · " + modelData.name : "") : (modelData.name || modelData.vendor || modelData.ip))
        subtitle: [modelData.ip, modelData.name ? modelData.vendor : "", modelData.services.join(", "), modelData.mac].filter(function(x) { return x !== "" }).join(" · ")
        clickable: true
        tip: "Copy " + modelData.ip
        onClicked: page.cc.copy(modelData.ip)
      }
    }
  }
}
