.pragma library

// Every Hyprland option the Control Center may read or write. Nothing outside
// this table is ever sent to `hyprctl eval`, and values are coerced to the
// declared type before they are serialized.
var OPTIONS = {
  "general:layout":                   { type: "string", choices: ["dwindle", "master", "scrolling"] },
  "general:gaps_in":                  { type: "int", min: 0, max: 40 },
  "general:gaps_out":                 { type: "int", min: 0, max: 80 },
  "general:border_size":              { type: "int", min: 0, max: 10 },
  "decoration:rounding":              { type: "int", min: 0, max: 30 },
  "decoration:active_opacity":        { type: "float", min: 0.3, max: 1 },
  "decoration:inactive_opacity":      { type: "float", min: 0.3, max: 1 },
  "decoration:dim_inactive":          { type: "bool" },
  "decoration:dim_strength":          { type: "float", min: 0, max: 1 },
  "decoration:blur:enabled":          { type: "bool" },
  "decoration:shadow:enabled":        { type: "bool" },
  "animations:enabled":               { type: "bool" },
  "scrolling:column_width":           { type: "float", min: 0.2, max: 1 },
  "scrolling:follow_focus":           { type: "bool" },
  "dwindle:preserve_split":           { type: "bool" },
  "master:new_status":                { type: "string", choices: ["master", "slave", "inherit"] },
  "misc:focus_on_activate":           { type: "bool" },
  "input:follow_mouse":               { type: "int", min: 0, max: 3 },
  "input:sensitivity":                { type: "float", min: -1, max: 1 },
  "input:natural_scroll":             { type: "bool" },
  "input:repeat_rate":                { type: "int", min: 10, max: 100 },
  "input:repeat_delay":               { type: "int", min: 150, max: 1000 },
  "input:touchpad:natural_scroll":    { type: "bool" },
  "input:touchpad:tap_to_click":      { type: "bool" },
  "input:touchpad:disable_while_typing": { type: "bool" },
  "input:kb_layout":                  { type: "string", readOnly: true }
}

function keys() { return Object.keys(OPTIONS) }

// One `hyprctl -j getoption` reply → a plain JS value.
function parseReply(line) {
  var o
  try { o = JSON.parse(line) } catch (e) { return null }
  if (!o || !OPTIONS[o.option]) return null
  var v
  if (o.css !== undefined) v = parseInt(String(o.css).split(" ")[0], 10)
  else if (o.int !== undefined) v = o.int
  else if (o.float !== undefined) v = o.float
  else if (o.bool !== undefined) v = o.bool
  else if (o.str !== undefined) v = String(o.str)
  return { key: o.option, value: coerce(o.option, v) }
}

function coerce(key, value) {
  var spec = OPTIONS[key]
  if (!spec) return undefined
  if (spec.type === "bool") return value === true || value === 1 || value === "1" || value === "true"
  if (spec.type === "int" || spec.type === "float") {
    var n = Number(value)
    if (!isFinite(n)) return undefined
    if (spec.type === "int") n = Math.round(n)
    else n = Math.round(n * 100) / 100
    if (spec.min !== undefined) n = Math.max(spec.min, n)
    if (spec.max !== undefined) n = Math.min(spec.max, n)
    return n
  }
  var s = String(value)
  if (spec.choices && spec.choices.indexOf(s) < 0) return undefined
  return s
}

function luaValue(v) {
  if (typeof v === "boolean") return v ? "true" : "false"
  if (typeof v === "number") return String(v)
  // Only fixed choices reach here; JSON quoting is valid Lua for them.
  return JSON.stringify(String(v))
}

function luaTable(obj, indent) {
  var pad = indent || ""
  var inner = pad + "\t"
  var lines = []
  var names = Object.keys(obj).sort()
  for (var i = 0; i < names.length; i++) {
    var k = names[i]
    if (!/^[a-z_]+$/.test(k)) continue
    var v = obj[k]
    if (v !== null && typeof v === "object") lines.push(inner + k + " = " + luaTable(v, inner) + ",")
    else lines.push(inner + k + " = " + luaValue(v) + ",")
  }
  return "{\n" + lines.join("\n") + "\n" + pad + "}"
}

// {"general:gaps_in": 8, ...} → nested object {general: {gaps_in: 8}}.
function nest(flat) {
  var root = {}
  for (var key in flat) {
    var spec = OPTIONS[key]
    if (!spec || spec.readOnly) continue
    var v = coerce(key, flat[key])
    if (v === undefined) continue
    var parts = key.split(":")
    var node = root
    for (var i = 0; i < parts.length - 1; i++) {
      if (!node[parts[i]] || typeof node[parts[i]] !== "object") node[parts[i]] = {}
      node = node[parts[i]]
    }
    node[parts[parts.length - 1]] = v
  }
  return root
}

function evalSnippet(key, value) {
  var one = {}
  one[key] = value
  return "hl.config(" + luaTable(nest(one), "").replace(/\s+/g, " ") + ")"
}

// Monitor overrides: {"eDP-1": {mode: "2880x1800@120.00", position: "0x0", scale: 1.5}}.
// A monitor is named by connector ("DP-1") or, for externals, by
// "desc:<make model serial>" so it keeps its place whichever port it's in.
// The name goes into generated Lua, so only plain printable text passes.
function safeMonitorName(name) {
  var n = String(name || "")
  return /^[A-Za-z0-9._-]+$/.test(n) || /^desc:[A-Za-z0-9 ._()\/,+-]{1,120}$/.test(n)
}

function cleanMonitor(name, cfg) {
  if (!safeMonitorName(name)) return null
  cfg = cfg || {}
  if (cfg.disabled === true) return { disabled: true }
  var mode = String(cfg.mode || "preferred")
  if (mode !== "preferred" && !/^\d{2,5}x\d{2,5}(@\d{1,3}(\.\d+)?)?$/.test(mode)) return null
  var position = String(cfg.position || "auto")
  if (position !== "auto" && !/^-?\d{1,5}x-?\d{1,5}$/.test(position)) return null
  var scale = Number(cfg.scale)
  if (!isFinite(scale) || scale < 0.25 || scale > 4) scale = 1
  var out = { mode: mode, position: position, scale: Math.round(scale * 1000) / 1000 }
  if (cfg.mirror && /^[A-Za-z0-9._-]+$/.test(String(cfg.mirror))) out.mirror = String(cfg.mirror)
  // Per-display extras: rotation, adaptive sync, 10-bit colour, colour mode
  // (sRGB / wide gamut / HDR) and how bright and saturated normal content is
  // in HDR. Only written when set.
  var t = Number(cfg.transform)
  if (t >= 1 && t <= 7 && Math.floor(t) === t) out.transform = t
  var vrr = Number(cfg.vrr)
  if (cfg.vrr !== undefined && (vrr === 0 || vrr === 1 || vrr === 2)) out.vrr = vrr
  if (Number(cfg.bitdepth) === 10) out.bitdepth = 10
  if (["auto", "srgb", "wide", "edid", "hdr", "hdredid"].indexOf(String(cfg.cm)) >= 0) out.cm = String(cfg.cm)
  if (String(out.cm || "").indexOf("hdr") === 0) {
    var b = Number(cfg.sdrbrightness), s = Number(cfg.sdrsaturation)
    if (b >= 0.5 && b <= 2) out.sdrbrightness = Math.round(b * 100) / 100
    if (s >= 0.5 && s <= 1.5) out.sdrsaturation = Math.round(s * 100) / 100
  }
  return out
}

function monitorLua(name, cfg) {
  var c = cleanMonitor(name, cfg)
  if (!c) return ""
  if (c.disabled) return "hl.monitor({ output = " + JSON.stringify(name) + ", disabled = true })"
  return "hl.monitor({ output = " + JSON.stringify(name) + ", mode = " + JSON.stringify(c.mode)
    + ", position = " + JSON.stringify(c.position) + ", scale = " + c.scale
    + (c.mirror ? ", mirror = " + JSON.stringify(c.mirror) : "")
    + (c.transform ? ", transform = " + c.transform : "")
    + (c.vrr !== undefined ? ", vrr = " + c.vrr : "")
    + (c.bitdepth ? ", bitdepth = 10" : "")
    + (c.cm ? ", cm = " + JSON.stringify(c.cm) : "")
    + (c.sdrbrightness ? ", sdrbrightness = " + c.sdrbrightness : "")
    + (c.sdrsaturation ? ", sdrsaturation = " + c.sdrsaturation : "") + " })"
}

function overridesFile(flat, monitors) {
  var body = luaTable(nest(flat), "")
  var mons = []
  for (var m in (monitors || {})) {
    var line = monitorLua(m, monitors[m])
    if (line) mons.push(line)
  }
  return "-- Written by the Control Center plugin (io.github.bahman777.control-center).\n"
    + "-- Settings you change in its window land here; delete this file or use\n"
    + "-- \"Reset window settings\" in the window to go back to your own config.\n"
    + "hl.config(" + body + ")\n"
    + (mons.length ? "\n-- Displays\n" + mons.join("\n") + "\n" : "")
}
