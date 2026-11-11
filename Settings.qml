import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "ui"
import "Icons.js" as Icons

// The Control Center window: a GNOME Settings-style sidebar of categories and
// a page per category. Summoned through the shell:
//   omarchy-shell shell toggle io.github.bahman777.control-center
//   omarchy-shell shell summon io.github.bahman777.control-center '{"page":"bluetooth"}'
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property string page: "wifi"
  property string query: ""

  readonly property string pluginId: (manifest && manifest.id) || "io.github.bahman777.control-center"
  readonly property alias runner: runner
  readonly property string buildStamp: String(Date.now())
  readonly property alias hypr: hypr

  readonly property var pages: [
    { id: "wifi",          title: "Wi-Fi",          icon: Icons.wifi,       file: "WifiPage.qml",          keys: "wireless network ssid hotspot password band speed qr" },
    { id: "network",       title: "Network",        icon: Icons.ethernet,   file: "NetworkPage.qml",       keys: "ethernet lan wired ip address dns gateway vpn wireguard proxy" },
    { id: "tailscale",     title: "Tailscale",      icon: Icons.vpn,        file: "TailscalePage.qml",     keys: "vpn tailnet exit node mesh magicdns peers machines taildrop" },
    { id: "bluetooth",     title: "Bluetooth",      icon: Icons.bluetooth,  file: "BluetoothPage.qml",     keys: "pair devices headset headphones mouse keyboard airpods" },
    { id: "sound",         title: "Sound",          icon: Icons.volume,     file: "SoundPage.qml",         keys: "audio volume output input speaker headset headphones microphone mic apps" },
    { id: "displays",      title: "Displays",       icon: Icons.monitor,    file: "DisplaysPage.qml",      keys: "monitor screen resolution refresh rate scale brightness night light text size mirror" },
    { id: "power",         title: "Power",          icon: Icons.batteryCharging, file: "PowerPage.qml",    keys: "battery power mode profile performance saver idle lock screensaver suspend shutdown reboot" },
    { id: "windows",       title: "Windows & Layout", icon: Icons.windows,  file: "WindowsPage.qml",       keys: "hyprland tiling layout dwindle master scrolling gaps borders rounding blur shadow animations opacity focus workspaces" },
    { id: "input",         title: "Keyboard & Mouse", icon: Icons.keyboard, file: "InputPage.qml",         keys: "keyboard layout repeat mouse touchpad trackpad scroll natural tap sensitivity" },
    { id: "appearance",    title: "Appearance",     icon: Icons.palette,    file: "AppearancePage.qml",    keys: "theme dark light font background wallpaper bar position corners" },
    { id: "notifications", title: "Notifications",  icon: Icons.bell,       file: "NotificationsPage.qml", keys: "do not disturb dnd silence alerts" },
    { id: "system",        title: "System",         icon: Icons.info,       file: "SystemPage.qml",        keys: "about hostname version kernel cpu memory disk update date time timezone language region" }
  ]

  readonly property var visiblePages: {
    var q = root.query.trim().toLowerCase()
    if (q === "") return root.pages
    return root.pages.filter(function(p) {
      return (p.title + " " + p.keys).toLowerCase().indexOf(q) >= 0
    })
  }

  readonly property var currentPage: {
    for (var i = 0; i < pages.length; i++) if (pages[i].id === page) return pages[i]
    return pages[0]
  }

  // ------------------------------------------------------------ helpers used by pages

  function firstParty(id) {
    return shell && typeof shell.firstPartyServiceFor === "function" ? shell.firstPartyServiceFor(id) : null
  }
  function summon(id, payload) {
    if (shell && typeof shell.summon === "function") shell.summon(id, payload || "{}")
  }
  function launchTerminal(cmd) {
    runner.detach(["omarchy-launch-floating-terminal-with-presentation", cmd])
  }
  function copy(text) {
    runner.run(["wl-copy", "--", String(text)], null)
    toast("Copied " + text)
  }
  property string toastText: ""
  function toast(text) { toastText = String(text); toastTimer.restart() }

  // ------------------------------------------------------------ shell contract

  function open(payloadJson) {
    try {
      var payload = payloadJson ? JSON.parse(payloadJson) : {}
      if (payload && payload.page) selectPage(String(payload.page))
    } catch (e) {}
    root.query = ""
    root.opened = true
    hypr.refresh()
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (shell && typeof shell.hide === "function") shell.hide(root.pluginId)
  }

  function selectPage(id) {
    for (var i = 0; i < pages.length; i++) if (pages[i].id === id) { root.page = id; return }
  }

  function stepPage(delta) {
    var list = visiblePages
    if (list.length === 0) return
    var idx = 0
    for (var i = 0; i < list.length; i++) if (list[i].id === page) idx = i
    idx = Math.max(0, Math.min(list.length - 1, idx + delta))
    page = list[idx].id
  }

  Runner { id: runner }
  HyprOptions { id: hypr; runner: runner }

  Timer { id: toastTimer; interval: 2200 }

  OverlayWindow {
    id: window
    shown: root.opened
    WlrLayershell.namespace: "control-center"

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(1080), window.width - Style.space(48))
      height: Math.min(Style.space(760), window.height - Style.space(48))
      radius: Math.max(Style.cornerRadius, 10)
      // A settings window full of text needs a solid surface even on glassy themes.
      color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1)
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: 0
      clip: true

      opacity: window.contentRevealed ? 1 : 0
      scale: window.contentRevealed ? 1 : 0.97
      Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut } }

      MouseArea { anchors.fill: parent }

      readonly property bool compact: width < Style.space(820)

      FocusScope {
        id: keys
        anchors.fill: parent
        anchors.margins: card.contentTopInset
        focus: true

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.query !== "") { root.query = ""; search.text = "" } else root.dismiss()
            event.accepted = true
          } else if ((event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) || event.key === Qt.Key_Slash) {
            search.forceActiveFocus(); event.accepted = true
          } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier))) {
            root.stepPage(1); event.accepted = true
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
            root.stepPage(-1); event.accepted = true
          }
        }

        // ---------------------------------------------------- sidebar
        Rectangle {
          id: sidebar
          anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
          width: card.compact ? Style.space(64) : Style.space(250)
          color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.03)

          Column {
            id: sideHead
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: Style.spacing.xl }
            spacing: Style.spacing.xl

            CcText {
              visible: !card.compact
              text: "Settings"
              font.pixelSize: Style.font.heading
              font.weight: Font.DemiBold
            }

            TextField {
              id: search
              visible: !card.compact
              width: parent.width
              placeholderText: "Search settings"
              foreground: Color.menu.text
              onTextChanged: {
                root.query = text
                if (root.visiblePages.length > 0 && root.visiblePages.map(function(p) { return p.id }).indexOf(root.page) < 0)
                  root.page = root.visiblePages[0].id
              }
              Keys.onDownPressed: function(e) { root.stepPage(1); e.accepted = true }
              Keys.onUpPressed: function(e) { root.stepPage(-1); e.accepted = true }
              Keys.onReturnPressed: keys.forceActiveFocus()
              Keys.onEscapePressed: function(e) {
                if (text !== "") text = ""; else root.dismiss()
                e.accepted = true
              }
            }
          }

          ListView {
            id: nav
            anchors { top: sideHead.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
            anchors.topMargin: Style.spacing.lg
            anchors.leftMargin: Style.spacing.md
            anchors.rightMargin: Style.spacing.md
            clip: true
            spacing: Style.spacing.xxs
            model: root.visiblePages
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: item
              required property var modelData
              readonly property bool current: modelData.id === root.page
              width: nav.width
              height: Style.space(38)
              radius: Math.max(6, Style.cornerRadius / 2)
              color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b,
                             current ? 0.10 : (hover.containsMouse ? 0.05 : 0))

              CcIcon {
                id: navIcon
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: card.compact ? Math.round((parent.width - width) / 2) : Style.spacing.md
                glyph: item.modelData.icon
                size: Style.font.icon
                color: item.current ? Color.accent : Color.menu.text
              }
              CcText {
                visible: !card.compact
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: navIcon.right
                anchors.leftMargin: Style.spacing.md
                anchors.right: parent.right
                text: item.modelData.title
                font.pixelSize: Style.font.subtitle
                font.weight: item.current ? Font.DemiBold : Font.Normal
              }
              MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.page = item.modelData.id; keys.forceActiveFocus() }
              }
            }
          }

          CcText {
            visible: root.visiblePages.length === 0 && !card.compact
            anchors.top: sideHead.bottom
            anchors.topMargin: Style.spacing.xxl
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No matching settings"
            color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
          }
        }

        Rectangle {
          id: divider
          anchors { top: parent.top; bottom: parent.bottom; left: sidebar.right }
          width: 1
          color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10)
        }

        // ---------------------------------------------------- content
        Item {
          id: content
          anchors { top: parent.top; bottom: parent.bottom; left: divider.right; right: parent.right }

          Item {
            id: titleBar
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: Style.space(56)

            CcText {
              anchors.centerIn: parent
              text: root.currentPage.title
              font.pixelSize: Style.font.heading
              font.weight: Font.DemiBold
            }

            Button {
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.xl
              anchors.verticalCenter: parent.verticalCenter
              iconText: Icons.close
              tooltipText: "Close (Esc)"
              foreground: Color.menu.text
              onClicked: root.dismiss()
            }
          }

          Loader {
            id: pageLoader
            anchors { top: titleBar.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
            asynchronous: false
            property string loadedId: ""
            function load() {
              if (!root.opened) { setSource(""); loadedId = ""; return }
              if (loadedId === root.currentPage.id && item) return
              loadedId = root.currentPage.id
              // The stamp changes with every plugin reload, so an updated page is
              // never served from the engine's component cache.
              setSource(Qt.resolvedUrl("pages/" + root.currentPage.file) + "?v=" + root.buildStamp, { cc: root })
            }
            onStatusChanged: if (status === Loader.Error) console.warn("control-center: page failed to load:", source)
            Component.onCompleted: load()
            Connections {
              target: root
              function onPageChanged() { pageLoader.load() }
              function onOpenedChanged() { pageLoader.load() }
            }
          }

          Rectangle {
            id: toastBox
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.huge
            anchors.horizontalCenter: parent.horizontalCenter
            visible: toastTimer.running
            width: toastLabel.implicitWidth + Style.spacing.huge * 2
            height: toastLabel.implicitHeight + Style.spacing.lg * 2
            radius: height / 2
            color: Color.tooltip.background
            border.width: 1
            border.color: Color.tooltip.border
            CcText {
              id: toastLabel
              anchors.centerIn: parent
              text: root.toastText
              color: Color.tooltip.text
            }
          }
        }
      }
    }
  }
}
