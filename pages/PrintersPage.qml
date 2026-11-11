import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Printers and scanners: what's installed, what's on the network, and adding
// or removing them. Admin changes go through pkexec, which Omarchy answers
// with its own password prompt.
CcPage {
  id: page

  property var printers: []          // installed: {name, uri, state, isDefault}
  property var jobs: []
  property var netPrinters: []       // discovered: {name, model, uri, addr}
  property var saneDevices: []       // {device, label}
  property var netScanners: []       // discovered: {name, url, addr}
  property bool discovering: false
  // Discovered printers/scanners checked one by one: uri/url -> "ready" | "offline" | "unreachable"
  property var health: ({})
  property var manualScanners: ({})  // name -> url, from sane-airscan's [devices]
  property bool showOffline: false
  function setHealth(key, v) { var h = Object.assign({}, health); h[key] = v; health = h }
  property bool scanningSane: false
  property string busy: ""

  readonly property string scannerIcon: String.fromCodePoint(0xF06AB)

  // avahi-browse -p escapes bytes as \DDD (decimal).
  function avahiUnescape(s) { return String(s).replace(/\\(\d{3})/g, function(m, d) { return String.fromCharCode(parseInt(d, 10)) }) }
  function txt(fields, key) {
    var m = new RegExp('"' + key + '=([^"]*)"').exec(fields)
    return m ? m[1] : ""
  }

  function refreshInstalled() {
    cc.runner.run(["lpstat", "-v"], function(code, out) {
      var uris = {}
      String(out).split("\n").forEach(function(l) {
        var m = /^device for ([^:]+):\s*(\S+)/.exec(l)
        if (m) uris[m[1]] = m[2]
      })
      page.cc.runner.run(["lpstat", "-d", "-p"], function(c2, o2) {
        var def = (/system default destination:\s*(\S+)/.exec(o2) || [])[1] || ""
        var states = {}
        String(o2).split("\n").forEach(function(l) { var m = /^printer (\S+) (?:is )?(\w+)/.exec(l); if (m) states[m[1]] = m[2] })
        page.printers = Object.keys(uris).map(function(n) { return { name: n, uri: uris[n], state: states[n] || "", isDefault: n === def } })
      })
    })
    cc.runner.run(["lpstat", "-o"], function(code, out) {
      page.jobs = String(out).split("\n").map(function(l) {
        var f = l.trim().split(/\s+/)
        return f.length >= 2 && /^[\w.@-]+-\d+$/.test(f[0]) ? { id: f[0], user: f[1] } : null
      }).filter(function(x) { return x !== null })
    })
  }

  function discover() {
    discovering = true
    cc.runner.sh("timeout 8 avahi-browse -rpt _ipp._tcp 2>/dev/null; timeout 8 avahi-browse -rpt _ipps._tcp 2>/dev/null; "
      + "timeout 8 avahi-browse -rpt _uscan._tcp 2>/dev/null; timeout 8 avahi-browse -rpt _uscans._tcp 2>/dev/null", [], function(code, out) {
      var printers = {}, scanners = {}
      String(out).split("\n").forEach(function(l) {
        if (l.indexOf("=;") !== 0) return
        var f = l.split(";")
        if (f.length < 10 || f[2] !== "IPv4") return
        var name = page.avahiUnescape(f[3]), type = f[4], addr = f[7], port = f[8], rest = f.slice(9).join(";")
        if (!/^[0-9.]+$/.test(addr) || !/^\d+$/.test(port)) return
        if (type.indexOf("Printer") >= 0 || type.indexOf("_ipp") >= 0) {
          var rp = page.txt(rest, "rp") || "ipp/print"
          if (!/^[A-Za-z0-9_\/.-]+$/.test(rp)) return
          var secure = type.indexOf("_ipps") >= 0 || type.indexOf("Secure") >= 0
          var uri = (secure ? "ipps://" : "ipp://") + addr + ":" + port + "/" + rp
          var key = addr + "/" + rp
          if (!printers[key] || secure) printers[key] = { name: name, model: page.txt(rest, "ty") || name, uri: uri, addr: addr, rp: rp }
        } else {
          var rs = page.txt(rest, "rs") || "eSCL"
          if (!/^[A-Za-z0-9_\/.-]+$/.test(rs)) return
          var s = type.indexOf("uscans") >= 0
          scanners[addr] = { name: name, url: (s ? "https://" : "http://") + addr + ":" + port + "/" + rs, addr: addr }
        }
      })
      page.netPrinters = Object.keys(printers).map(function(k) { return printers[k] })
      page.netPrinters.forEach(function(n) { page.probePrinter(n.uri) })
      page.netScanners = Object.keys(scanners).map(function(k) { return scanners[k] })
      page.discovering = false
    })
  }

  // A queue shared by another computer stays advertised after its printer is
  // gone; the printer itself says "offline-report" or doesn't answer at all.
  function probePrinter(uri) {
    cc.runner.run(["timeout", "6", "ipptool", "-T", "5", "-tv", uri, "get-printer-attributes.test"], function(code, out) {
      var o = String(out)
      var v = !/printer-state \(enum\)/.test(o) ? "unreachable"
        : /printer-state-reasons[^\n]*offline-report/.test(o) || /printer-state \(enum\) = stopped/.test(o) ? "offline" : "ready"
      page.setHealth(uri, v)
    })
  }
  function probeScanner(key, host, port) {
    if (!/^[A-Za-z0-9.:\[\]-]+$/.test(host) || !/^\d+$/.test(String(port))) { setHealth(key, "unreachable"); return }
    cc.runner.run(["timeout", "2", "bash", "-c", 'exec 3<>"/dev/tcp/$1/$2"', "probe", host, String(port)], function(code) {
      page.setHealth(key, code === 0 ? "ready" : "unreachable")
    })
  }
  function hostPort(url) {
    var m = /^(https?):\/\/([^\/:]+)(?::(\d+))?/.exec(String(url))
    return m ? { host: m[2], port: m[3] || (m[1] === "https" ? "443" : "80") } : null
  }
  function readAirscanConf() {
    cc.runner.run(["cat", "/etc/sane.d/airscan.conf"], function(code, out) {
      var inDev = false, m = {}
      String(out).split("\n").forEach(function(l) {
        var t = l.trim()
        if (/^\[/.test(t)) { inDev = t === "[devices]"; return }
        if (!inDev || t === "" || t[0] === "#" || t[0] === ";") return
        var kv = /^"?([^"=]+?)"?\s*=\s*(\S+)/.exec(t)
        if (kv) m[kv[1].trim()] = kv[2]
      })
      page.manualScanners = m
    })
  }
  function removeScanner(name) {
    var n = String(name)
    if (!/^[A-Za-z0-9 _.-]+$/.test(n)) return
    busy = n
    // Deletes the `name = url` line (quoted or not) from [devices].
    var esc = n.replace(/\./g, "\\.")
    cc.runner.run(["pkexec", "sed", "-i", "-E", '/^\\s*"?' + esc + '"?\\s*=/d', "/etc/sane.d/airscan.conf"], function(code) {
      page.busy = ""
      page.cc.toast(code === 0 ? "Removed scanner " + n : "Scanner not removed")
      page.readAirscanConf(); page.scanSane()
    })
  }
  // One row per physical scanner: the escl and airscan backends often both
  // find the same device. Each row knows its address and whether you added it.
  readonly property var scanners: {
    var seen = {}, out = []
    saneDevices.forEach(function(d) {
      var label = d.label.replace(/^eSCL\s+/, "")
      var key = label.toLowerCase()
      var manualName = d.device.indexOf("airscan:") === 0 ? d.device.split(":").slice(2).join(":") : ""
      var url = manualScanners[manualName] || (d.device.indexOf("escl:") === 0 ? d.device.slice(5) : "")
      var row = { device: d.device, label: label, url: url, manual: manualName !== "" && manualScanners[manualName] !== undefined ? manualName : "" }
      if (seen[key] !== undefined) { if (row.manual && !out[seen[key]].manual) out[seen[key]] = row; return }
      seen[key] = out.length; out.push(row)
    })
    return out
  }
  onScannersChanged: scanners.forEach(function(sc) {
    var hp = hostPort(sc.url)
    if (hp && health[sc.device] === undefined) probeScanner(sc.device, hp.host, hp.port)
  })
  function sharedBy(name) { var i = String(name).lastIndexOf(" @ "); return i > 0 ? String(name).slice(i + 3).replace(/\s*\(\d+\)$/, "") : "" }

  function scanSane() {
    scanningSane = true
    cc.runner.run(["timeout", "25", "scanimage", "-f", "%d|%v %m%n", "-L"], function(code, out) {
      page.saneDevices = String(out).split("\n").map(function(l) {
        var i = l.indexOf("|")
        if (i <= 0) return null
        var d = l.slice(0, i)
        return /^[a-z0-9_]+:\S+$/.test(d) && d.indexOf("v4l:") !== 0 ? { device: d, label: l.slice(i + 1).trim() } : null
      }).filter(function(x) { return x !== null })
      page.scanningSane = false
    })
  }

  Component.onCompleted: { refreshInstalled(); discover(); readAirscanConf(); scanSane() }
  Timer { interval: 5000; running: true; repeat: true; onTriggered: page.refreshInstalled() }

  readonly property var notInstalled: netPrinters.filter(function(n) {
    return !printers.some(function(p) { return p.uri.indexOf(n.addr) >= 0 && p.uri.indexOf(n.rp) >= 0 })
  })
  readonly property var newPrinters: notInstalled.filter(function(n) { var h = health[n.uri]; return h === undefined || h === "ready" })
  readonly property var deadPrinters: notInstalled.filter(function(n) { var h = health[n.uri]; return h === "offline" || h === "unreachable" })
  readonly property var newScanners: netScanners.filter(function(n) {
    return !saneDevices.some(function(d) { return d.device.indexOf(n.addr) >= 0 })
  })

  function queueName(s) {
    var n = String(s).replace(/[^A-Za-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 60)
    return n || "Printer"
  }
  function addPrinter(name, uri) {
    if (!/^ipps?:\/\/[A-Za-z0-9.:\[\]-]+(:\d+)?\/[A-Za-z0-9_\/.-]*$/.test(uri)) { cc.toast("That address doesn't look like a printer"); return }
    var q = queueName(name)
    busy = q
    // Driverless (IPP Everywhere): no vendor driver needed for modern printers.
    cc.runner.run(["pkexec", "lpadmin", "-p", q, "-E", "-v", uri, "-m", "everywhere"], function(code) {
      page.busy = ""
      page.cc.toast(code === 0 ? "Added " + q : code === 126 || code === 127 ? "Cancelled" : "Could not add " + q + " (is it an IPP Everywhere printer?)")
      page.refreshInstalled()
    })
  }
  function removePrinter(name) {
    if (!/^[\w.@-]+$/.test(name)) return
    busy = name
    cc.runner.run(["pkexec", "lpadmin", "-x", name], function(code) {
      page.busy = ""
      page.cc.toast(code === 0 ? "Removed " + name : "Not removed")
      page.refreshInstalled()
    })
  }
  function addScanner(name, url) {
    var n = String(name).replace(/[^A-Za-z0-9 _.-]+/g, "").trim().slice(0, 40)
    if (n === "" || !/^https?:\/\/[A-Za-z0-9.:\[\]-]+(:\d+)?\/[A-Za-z0-9_\/.-]*$/.test(url)) { cc.toast("Enter a name and an eSCL address"); return }
    busy = n
    // Adds `"Name" = URL` under [devices] in sane-airscan's config.
    cc.runner.run(["pkexec", "sed", "-i", "/^\\[devices\\]/a \"" + n + "\" = " + url, "/etc/sane.d/airscan.conf"], function(code) {
      page.busy = ""
      page.cc.toast(code === 0 ? "Added scanner " + n : "Scanner not added")
      page.scanSane()
    })
  }

  // ------------------------------------------------------------ printers
  CcGroup {
    title: "Printers"
    subtitle: page.printers.length === 0 ? "No printers yet. Add one below." : "Click a printer to make it your default"
    Repeater {
      model: page.printers
      delegate: CcRow {
        required property var modelData
        icon: Icons.printer
        iconColor: modelData.isDefault ? page.cc.accent : page.cc.fg
        title: modelData.name.replace(/_/g, " ") + (modelData.isDefault ? "  · default" : "")
        subtitle: (modelData.state || "") + " · " + modelData.uri
        clickable: !modelData.isDefault
        tip: "Make this your default printer"
        onClicked: page.cc.runner.run(["lpoptions", "-d", modelData.name], function() { page.refreshInstalled() })
        CcButton {
          text: page.busy === modelData.name ? "Removing…" : "Remove"
          tooltipText: "Asks for your password"
          onClicked: page.removePrinter(modelData.name)
        }
      }
    }
  }

  CcGroup {
    visible: page.jobs.length > 0
    title: "Print queue"
    header: [ CcButton { text: "Cancel all"; onClicked: page.cc.runner.run(["cancel", "-a"], function() { page.refreshInstalled() }) } ]
    Repeater {
      model: page.jobs
      delegate: CcRow {
        required property var modelData
        title: "Job " + modelData.id
        subtitle: modelData.user
        CcButton { text: "Cancel"; onClicked: page.cc.runner.run(["cancel", modelData.id], function() { page.refreshInstalled() }) }
      }
    }
  }

  CcGroup {
    title: "Add a printer"
    subtitle: page.discovering ? "Looking for printers on your network…"
      : page.newPrinters.length ? "Found on your network. Adding asks for your password." : "No new printers found on your network"
    header: [ CcButton { text: page.discovering ? "Searching…" : "Search again"; onClicked: if (!page.discovering) page.discover() } ]
    Repeater {
      model: page.newPrinters
      delegate: CcRow {
        required property var modelData
        icon: Icons.printer
        title: modelData.model
        subtitle: (page.sharedBy(modelData.name) ? "Shared by " + page.sharedBy(modelData.name) : "Network printer")
          + " · " + modelData.addr + (page.health[modelData.uri] === undefined ? " · checking…" : "")
        CcButton {
          text: page.busy === page.queueName(modelData.model) ? "Adding…" : "Add"
          tooltipText: "Add this printer (asks for your password)"
          onClicked: page.addPrinter(modelData.model, modelData.uri)
        }
      }
    }
    CcRow {
      visible: page.deadPrinters.length > 0
      title: page.deadPrinters.length + (page.deadPrinters.length === 1 ? " printer is" : " printers are") + " advertised but not working"
      subtitle: "Usually a computer still sharing a printer that's gone"
      clickable: true
      chevron: true
      tip: page.showOffline ? "Hide them" : "Show them"
      onClicked: page.showOffline = !page.showOffline
    }
    Repeater {
      model: page.showOffline ? page.deadPrinters : []
      delegate: CcRow {
        required property var modelData
        dim: true
        icon: Icons.printer
        title: modelData.model
        subtitle: (page.health[modelData.uri] === "offline" ? "Reported offline" : "Not answering")
          + (page.sharedBy(modelData.name) ? " by " + page.sharedBy(modelData.name) : "") + " · " + modelData.addr
      }
    }
    CcRow {
      title: "Add by address"
      subtitle: "IP address or ipp:// address of the printer"
      TextField {
        id: addr
        width: Style.space(200)
        placeholderText: "e.g. 192.168.1.50"
        foreground: page.cc.fg
        property bool ccFocusable: visible
        property bool hasCursor: false
        function ccActivate() { forceActiveFocus() }
        Keys.onReturnPressed: addAddr.clicked()
      }
      CcButton {
        id: addAddr
        text: "Add"
        onClicked: {
          var t = addr.text.trim()
          var uri = /^ipps?:\/\//.test(t) ? t : "ipp://" + t + "/ipp/print"
          page.addPrinter(t.replace(/^ipps?:\/\//, "").split(/[:\/]/)[0], uri)
          addr.text = ""
        }
      }
    }
    CcRow {
      title: "Advanced printer setup"
      subtitle: "Drivers, USB printers and printer options"
      clickable: true
      external: true
      tip: "Opens the system printer tool"
      onClicked: page.cc.launch(["system-config-printer"], 0)
    }
  }

  // ------------------------------------------------------------ scanners
  CcGroup {
    title: "Scanners"
    subtitle: page.scanningSane ? "Looking for scanners (network ones take a few seconds)…"
      : page.scanners.length ? "Click one to scan a document" : "No scanners found"
    header: [ CcButton { text: page.scanningSane ? "Searching…" : "Search again"; onClicked: if (!page.scanningSane) page.scanSane() } ]
    Repeater {
      model: page.scanners
      delegate: CcRow {
        required property var modelData
        readonly property bool dead: page.health[modelData.device] === "unreachable"
        readonly property var hp: page.hostPort(modelData.url)
        dim: dead
        icon: page.scannerIcon
        title: modelData.label
        subtitle: (dead ? "Not reachable" : hp ? "Network scanner" : "Found automatically")
          + (hp ? " · " + hp.host : "") + (modelData.manual ? " · added by hand" : "")
        clickable: !dead
        external: !dead
        tip: dead ? "" : "Scan with Document Scanner"
        onClicked: page.cc.launch(["simple-scan", modelData.device], 0)
        CcButton {
          visible: modelData.manual !== ""
          text: page.busy === modelData.manual ? "Removing…" : "Remove"
          tooltipText: "Remove this scanner (asks for your password)"
          onClicked: page.removeScanner(modelData.manual)
        }
      }
    }
  }

  CcGroup {
    title: "Add a scanner"
    subtitle: page.newScanners.length ? "On your network but not yet usable. Adding asks for your password." : "Network scanners are usually found automatically"
    Repeater {
      model: page.newScanners
      delegate: CcRow {
        required property var modelData
        icon: page.scannerIcon
        title: modelData.name
        subtitle: modelData.url
        CcButton { text: page.busy === modelData.name ? "Adding…" : "Add"; onClicked: page.addScanner(modelData.name, modelData.url) }
      }
    }
    CcRow {
      title: "Add by address"
      subtitle: "Name and eSCL address, e.g. http://192.168.1.31/eSCL"
      TextField {
        id: scanName
        width: Style.space(110)
        placeholderText: "Name"
        foreground: page.cc.fg
        property bool ccFocusable: visible
        property bool hasCursor: false
        function ccActivate() { forceActiveFocus() }
      }
      TextField {
        id: scanUrl
        width: Style.space(190)
        placeholderText: "http://…/eSCL"
        foreground: page.cc.fg
        property bool ccFocusable: visible
        property bool hasCursor: false
        function ccActivate() { forceActiveFocus() }
        Keys.onReturnPressed: addScan.clicked()
      }
      CcButton {
        id: addScan
        text: "Add"
        onClicked: { page.addScanner(scanName.text, scanUrl.text.trim()); scanName.text = ""; scanUrl.text = "" }
      }
    }
  }
}
