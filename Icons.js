.pragma library

// Nerd Font Material Design glyphs, by code point so the source stays ASCII.
function g(cp) { return String.fromCodePoint(cp) }

var wifi = g(0xF05A9), wifiOff = g(0xF05AA)
var wifi1 = g(0xF091F), wifi2 = g(0xF0922), wifi3 = g(0xF0925), wifi4 = g(0xF0928)
var ethernet = g(0xF0200), lan = g(0xF0318), vpn = g(0xF0582), web = g(0xF059F)
var bluetooth = g(0xF00AF), bluetoothOff = g(0xF00B2), bluetoothConnected = g(0xF00B1)
var volume = g(0xF057E), volumeOff = g(0xF0581), headphones = g(0xF02CB), headset = g(0xF02CE)
var microphone = g(0xF036C), microphoneOff = g(0xF036D), speaker = g(0xF04C3)
var monitor = g(0xF0379), brightness = g(0xF00DF), nightlight = g(0xF0594), textSize = g(0xF0284)
var battery = g(0xF0079), batteryCharging = g(0xF0084), bolt = g(0xF140B), power = g(0xF0425)
var windows = g(0xF0574), keyboard = g(0xF030C), mouse = g(0xF037D), touchpad = g(0xF0322)
var palette = g(0xF03D8), bell = g(0xF009A), bellOff = g(0xF009B), info = g(0xF02FC)
var cog = g(0xF0493), lock = g(0xF033E), refresh = g(0xF0450), search = g(0xF0349)
var calendar = g(0xF00ED), music = g(0xF0387)
var check = g(0xF012C), close = g(0xF0156), phone = g(0xF011C), laptop = g(0xF0322)
var computer = g(0xF0379), watch = g(0xF0597), gamepad = g(0xF0297), printer = g(0xF042A)
var app = g(0xF003B), clock = g(0xF0954), translate = g(0xF05CA), harddisk = g(0xF02CA)
var chip = g(0xF061A), memory = g(0xF035B), image = g(0xF02E9), formatFont = g(0xF0284)
var server = g(0xF048B), dots = g(0xF01D8), exit = g(0xF0206), shield = g(0xF0498)
var wallpaper = g(0xF02F9), firewall = g(0xF0565), glass = g(0xF00B5)
var sleep = g(0xF04B2), restart = g(0xF0709), logout = g(0xF0343), eye = g(0xF0208)

function wifiStrength(s) {
  // Quickshell reports 0..1.
  if (s >= 0.75) return wifi4
  if (s >= 0.5) return wifi3
  if (s >= 0.25) return wifi2
  return wifi1
}

function bluetoothDevice(iconName) {
  var n = String(iconName || "")
  if (n.indexOf("headset") >= 0) return headset
  if (n.indexOf("headphone") >= 0 || n.indexOf("audio-card") >= 0) return headphones
  if (n.indexOf("speaker") >= 0 || n.indexOf("audio") >= 0) return speaker
  if (n.indexOf("keyboard") >= 0) return keyboard
  if (n.indexOf("mouse") >= 0 || n.indexOf("tablet") >= 0) return mouse
  if (n.indexOf("phone") >= 0) return phone
  if (n.indexOf("computer") >= 0 || n.indexOf("laptop") >= 0) return laptop
  if (n.indexOf("gaming") >= 0 || n.indexOf("joystick") >= 0) return gamepad
  if (n.indexOf("watch") >= 0) return watch
  if (n.indexOf("printer") >= 0) return printer
  return bluetooth
}
