.pragma library
.import "Icons.js" as Icons

// Settings pages shown inside the Quick Settings panel.
var PAGES = [
  { id: "wifi",          title: "Wi-Fi",            icon: Icons.wifi,            file: "WifiPage.qml",          keys: "wireless network ssid hotspot password band speed" },
  { id: "network",       title: "Network",          icon: Icons.ethernet,        file: "NetworkPage.qml",       keys: "ethernet lan wired ip address dns gateway vpn wireguard proxy hostname" },
  { id: "tailscale",     title: "Tailscale",        icon: Icons.vpn,             file: "TailscalePage.qml",     keys: "vpn tailnet exit node mesh magicdns peers machines taildrop" },
  { id: "bluetooth",     title: "Bluetooth",        icon: Icons.bluetooth,       file: "BluetoothPage.qml",     keys: "pair devices headset headphones mouse keyboard airpods discoverable" },
  { id: "sound",         title: "Sound",            icon: Icons.volume,          file: "SoundPage.qml",         keys: "audio volume output input speaker headset headphones microphone mic apps" },
  { id: "displays",      title: "Displays",         icon: Icons.monitor,         file: "DisplaysPage.qml",      keys: "monitor screen resolution refresh rate scale brightness night light text size mirror" },
  { id: "printers",      title: "Printers & Scanners", icon: Icons.printer,       file: "PrintersPage.qml",      keys: "printer print scanner scan cups ipp airprint escl sane document" },
  { id: "firewall",      title: "Firewall",         icon: Icons.firewall,          file: "FirewallPage.qml",      keys: "firewall ufw ports open port block incoming security allow deny" },
  { id: "devices",       title: "Network Devices",  icon: Icons.lan,             file: "DevicesPage.qml",       keys: "lan devices network scan neighbours ip mac router hosts who is connected" },
  { id: "power",         title: "Power",            icon: Icons.batteryCharging, file: "PowerPage.qml",         keys: "battery power mode profile performance saver idle lock screensaver suspend shutdown reboot" },
  { id: "windows",       title: "Windows & Layout", icon: Icons.windows,         file: "WindowsPage.qml",       keys: "hyprland tiling layout dwindle master scrolling gaps borders rounding blur shadow animations opacity focus workspaces" },
  { id: "input",         title: "Keyboard & Mouse", icon: Icons.keyboard,        file: "InputPage.qml",         keys: "keyboard layout repeat mouse touchpad trackpad scroll natural tap sensitivity" },
  { id: "glass",         title: "Glass",            icon: Icons.glass,         file: "GlassPage.qml",         needs: "hyprglass", keys: "glass hyprglass bevel blur frosted liquid transparency opacity refraction lens tint border" },
  { id: "appearance",    title: "Appearance",       icon: Icons.palette,         file: "AppearancePage.qml",    keys: "theme dark light font background wallpaper bar position corners" },
  { id: "calendar",      title: "Calendar",         icon: Icons.calendar,        file: "CalendarPage.qml",      keys: "calendar events meetings agenda google ical ics schedule month" },
  { id: "notifications", title: "Notifications",    icon: Icons.bell,            file: "NotificationsPage.qml", keys: "do not disturb dnd silence alerts" },
  { id: "system",        title: "System",           icon: Icons.info,            file: "SystemPage.qml",        keys: "about hostname version kernel cpu memory disk update date time timezone language region" }
]

function find(id) {
  for (var i = 0; i < PAGES.length; i++) if (PAGES[i].id === id) return PAGES[i]
  return null
}

function filter(query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return PAGES
  return PAGES.filter(function(p) { return (p.title + " " + p.keys).toLowerCase().indexOf(q) >= 0 })
}
