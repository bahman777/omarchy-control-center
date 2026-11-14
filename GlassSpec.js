.pragma library

// hyprglass (github.com/hyprnux/hyprglass) settings the Glass page edits:
// label, plain-language help, range and the plugin's own default. Types:
// "float", "int", "color" (0xRRGGBBAA, alpha = strength) and "bool".
var GROUPS = [
  { id: "glass", title: "Glass", subtitle: "The body of the glass behind each window",
    where: "Shows wherever the window is see-through: the clearest of all." },
  { id: "edge", title: "Edge & lens", subtitle: "How the rim bends and catches light",
    where: "Bends what's behind the window, so it needs detail there: drag the window partly over another one. Lens bulge and Edge width shape the dome." },
  { id: "bevel", title: "Bevel & light", subtitle: "The lit line along the edge and where light comes from",
    where: "Only in a thin band right at the window's edge, under the border." },
  { id: "color", title: "Colour", subtitle: "How what's behind the glass is toned",
    where: "Everywhere behind the window; easy to see." },
  { id: "more", title: "More", subtitle: "Frost, grain and special effects",
    where: "Frost shows where windows overlap; grain everywhere." }
]

// Starting points of our own, alongside your presets.
var LOOKS = [
  { name: "Dome", help: "A rounded, magnifying dome: wide soft edge, strong centre bulge, top shine",
    values: { glass_opacity: 1, blur_strength: 1.4, edge_thickness_px: 70, edge_height: 0, refraction_strength: 0.9,
              refraction_flow: 0, refraction_spread: 1, lens_distortion: 1, chromatic_aberration: 0.35,
              fresnel_strength: 0.7, fresnel_reflection: 0, specular_strength: 1, specular_angle: 0,
              bevel_strength: 0.5, bevel_size: 2, bevel_shadow: 0.4 } },
  { name: "Clear lens", help: "Flat clear centre with a crisp lens rim",
    values: { glass_opacity: 1, blur_strength: 0.8, edge_thickness_px: 18, edge_height: 40, refraction_strength: 1,
              refraction_spread: 0.2, lens_distortion: 0.1, chromatic_aberration: 0.5, fresnel_strength: 0.9,
              fresnel_reflection: 0.5, specular_strength: 0.9, bevel_strength: 0.8, bevel_size: 2.5, bevel_shadow: 0.5 } }
]
function look(name) { for (var i = 0; i < LOOKS.length; i++) if (LOOKS[i].name === name) return LOOKS[i]; return null }

var SETTINGS = [
  { key: "glass_opacity", group: "glass", label: "Glass opacity", help: "How much of the glass effect shows", type: "float", min: 0, max: 1, def: 1.0 },
  { key: "blur_strength", group: "glass", label: "Blur", help: "How frosted the background looks", type: "float", min: 0, max: 5, def: 2.0 },
  { key: "blur_iterations", group: "glass", label: "Blur smoothness", help: "Blur passes: more is smoother and costs more GPU", type: "int", min: 1, max: 5, def: 3 },
  { key: "tint_color", group: "glass", label: "Tint", help: "Colour laid over the glass; the last two digits are its strength", type: "color", def: 0x8899aa22 },

  { key: "edge_thickness_px", group: "edge", label: "Edge width", help: "Width of the curved rim in pixels (0 uses a share of the window size)", type: "float", min: 0, max: 60, def: 0 },
  { key: "edge_height", group: "edge", label: "Lens edge", help: "Turns the rim into a lens with a crisp bend and a flat centre (0 is off)", type: "float", min: 0, max: 80, def: 0 },
  { key: "refraction_strength", group: "edge", label: "Refraction", help: "How strongly the rim bends what's behind it", type: "float", min: 0, max: 1, def: 0.6 },
  { key: "refraction_flow", group: "edge", label: "Refraction direction", help: "0 pulls toward the centre, 1 along the edges", type: "float", min: 0, max: 1, def: 0 },
  { key: "refraction_spread", group: "edge", label: "Refraction reach", help: "1 bends across the whole window, 0 only at the rim", type: "float", min: 0, max: 1, def: 1 },
  { key: "chromatic_aberration", group: "edge", label: "Rainbow fringe", help: "Colour splitting at the edges, like a prism", type: "float", min: 0, max: 1, def: 0.5 },
  { key: "lens_distortion", group: "edge", label: "Lens bulge", help: "Magnifies the centre slightly, like a dome", type: "float", min: 0, max: 1, def: 0.5 },
  { key: "fresnel_strength", group: "edge", label: "Edge glow", help: "Glow along the rim", type: "float", min: 0, max: 1, def: 0.6 },
  { key: "fresnel_color", group: "edge", label: "Edge glow colour", help: "Last two digits: how much it replaces white", type: "color", def: 0xffffff00 },
  { key: "fresnel_tint", group: "edge", label: "Edge glow from behind", help: "0 uses the glow colour, 1 the colours behind the glass", type: "float", min: 0, max: 1, def: 0 },
  { key: "fresnel_reflection", group: "edge", label: "Edge reflection", help: "The lens edge mirrors its surroundings (needs Lens edge)", type: "float", min: 0, max: 1, def: 0 },

  { key: "bevel_strength", group: "bevel", label: "Bevel", help: "The lit line along the glass edge", type: "float", min: 0, max: 1, def: 0 },
  { key: "bevel_size", group: "bevel", label: "Bevel width", help: "Width of the bevel line in pixels", type: "float", min: 0, max: 24, def: 6 },
  { key: "bevel_color", group: "bevel", label: "Bevel colour", help: "Last two digits: how much it replaces white; dark colours give a dark line", type: "color", def: 0xffffff00 },
  { key: "bevel_tint", group: "bevel", label: "Bevel from behind", help: "0 uses the bevel colour, 1 the colours behind the glass", type: "float", min: 0, max: 1, def: 0 },
  { key: "bevel_angle", group: "bevel", label: "Bevel light direction", help: "Degrees: 0 from the top, 90 from the right", type: "float", min: 0, max: 360, def: 315 },
  { key: "bevel_shadow", group: "bevel", label: "Bevel shadow", help: "Darkens the side away from the light, for a 3-D edge", type: "float", min: 0, max: 1, def: 0 },
  { key: "specular_strength", group: "bevel", label: "Shine", help: "Brightness of the highlight", type: "float", min: 0, max: 1, def: 0.8 },
  { key: "specular_angle", group: "bevel", label: "Shine direction", help: "Degrees: 0 from the top, 90 from the right", type: "float", min: 0, max: 360, def: 0 },
  { key: "focus_light", group: "bevel", label: "Focus light", help: "Light along the edge of the active window", type: "float", min: 0, max: 1, def: 0 },
  { key: "focus_light_color", group: "bevel", label: "Focus light colour", help: "Last two digits: how much it replaces white", type: "color", def: 0xffffff00 },

  { key: "brightness", group: "color", label: "Brightness", help: "Of what's behind the glass", type: "float", min: 0.3, max: 1.6, def: 0.82 },
  { key: "contrast", group: "color", label: "Contrast", type: "float", min: 0.5, max: 1.5, def: 0.9 },
  { key: "saturation", group: "color", label: "Saturation", help: "0 is greyscale", type: "float", min: 0, max: 1.5, def: 0.8 },
  { key: "vibrancy", group: "color", label: "Vibrancy", help: "Boosts muted colours", type: "float", min: 0, max: 1, def: 0.15 },
  { key: "vibrancy_darkness", group: "color", label: "Vibrancy in shadows", help: "Holds vibrancy back in dark areas", type: "float", min: 0, max: 2, def: 0 },
  { key: "adaptive_dim", group: "color", label: "Dim bright areas", help: "Keeps white backgrounds from glaring through", type: "float", min: 0, max: 1, def: 0.4 },
  { key: "adaptive_boost", group: "color", label: "Lift dark areas", type: "float", min: 0, max: 1, def: 0 },

  { key: "frost", group: "more", label: "Frost", help: "Blurs more where windows are behind, stays clear over the wallpaper", type: "float", min: 0, max: 1, def: 0 },
  { key: "frost_blur", group: "more", label: "Frost blur", help: "Extra blur of the frost (needs Frost)", type: "float", min: 0.5, max: 3, def: 3 },
  { key: "noise_strength", group: "more", label: "Grain", help: "Frosted grain over the glass", type: "float", min: 0, max: 1, def: 0 },
  { key: "self_sample", group: "more", label: "Window shows through", help: "Mixes the window's own content into the glass", type: "float", min: 0, max: 1, def: 0 },
  { key: "xray", group: "more", label: "X-ray", help: "Hides the windows under the glass: only the wallpaper shows", type: "bool", def: false }
]

function byKey(k) {
  for (var i = 0; i < SETTINGS.length; i++) if (SETTINGS[i].key === k) return SETTINGS[i]
  return null
}

function defaults() {
  var o = {}
  SETTINGS.forEach(function(s) { o[s.key] = s.def })
  return o
}

// Clamp and type-check one value; undefined when it can't be used.
function clean(key, v) {
  var s = byKey(key)
  if (!s) return undefined
  if (s.type === "bool") return v === true || v === 1 || v === "true"
  if (s.type === "color") {
    var n = typeof v === "string" ? parseInt(v.replace(/^#|^0x/i, ""), 16) : Number(v)
    if (!isFinite(n) || n < 0 || n > 0xFFFFFFFF) return undefined
    return Math.floor(n)
  }
  var x = Number(v)
  if (!isFinite(x)) return undefined
  x = Math.max(s.min, Math.min(s.max, x))
  return s.type === "int" ? Math.round(x) : Math.round(x * 1000) / 1000
}

function hex(n) {
  var h = (Number(n) >>> 0).toString(16)
  while (h.length < 8) h = "0" + h
  return h
}

// { key: value } -> Lua table body: `bevel_size = 6, tint_color = 0x8899aa22`
function luaFields(values) {
  var out = []
  SETTINGS.forEach(function(s) {
    var v = clean(s.key, values[s.key])
    if (v === undefined) return
    out.push(s.key + " = " + (s.type === "color" ? "0x" + hex(v) : s.type === "bool" ? (v ? "true" : "false") : String(v)))
  })
  return out.join(", ")
}

// Live: the plugin applies its global settings at once (presets only on a
// config load), so tuning sets the globals and points windows at a preset
// name that doesn't exist, letting the globals through.
var LIVE_PRESET = "control_center_live"
function liveSnippet(values) {
  return "hl.plugin.hyprglass.config({ default_preset = \"" + LIVE_PRESET + "\", " + luaFields(values) + " })"
}

// Saved: a preset of our own in control-center.lua, made the default.
var SAVED_PRESET = "control_center"
function savedLua(values) {
  return "if hl.plugin and hl.plugin.hyprglass then\n"
    + "  local hg = hl.plugin.hyprglass\n"
    + "  hg.preset(\"" + SAVED_PRESET + "\", { " + luaFields(values) + " })\n"
    + "  hg.config({ default_preset = \"" + SAVED_PRESET + "\" })\n"
    + "end\n"
}

// ------------------------------------------------------------ glass border
// Hyprland borders take up to 10 colour stops with alpha, and the
// `borderangle` loop animation turns them. Mostly see-through frosted stops
// plus a bright glint read as light travelling around a glass rim. The rim
// can take its tint from the wallpaper's colours (see tools/wallpaper-palette.py).
var BORDER_DEFAULTS = {
  style: "glass",          // "glass" or "own" (leave the config's border alone)
  mode: "travel",          // "travel" (light circles), "sparkle" (random sparks), "still"
  sparkRate: 20,           // sparkle: sparks per minute, on average
  sparkSize: "medium",     // "small" (1 point lit), "medium" (3), "large" (5)
  sparkHold: 0.6,          // seconds a spark stays lit before it fades
  sparkColor: "white",     // "white" or "wallpaper" (the glint takes the wallpaper's accent)
  width: 6,                // px
  followWallpaper: true,
  wallpaperMix: 0.55,      // 0 white rim .. 1 the wallpaper's colour
  rimColor: 0xcfe8ff,      // when not following the wallpaper (RRGGBB)
  rimStrength: 0.28,       // rim opacity
  glint: 0.93,             // glint opacity
  glintColor: 0xffffff,    // RRGGBB
  glintLength: "short",    // "short" spark or "long" sheen
  seconds: 8,              // one turn
  palette: null            // { accent: "rrggbb", base: "rrggbb", path }
}

function cleanBorder(b) {
  b = b || {}
  var d = BORDER_DEFAULTS, o = {}
  o.style = b.style === "own" ? "own" : "glass"
  o.mode = b.mode === "sparkle" || b.mode === "still" ? b.mode : "travel"
  o.sparkColor = b.sparkColor === "wallpaper" ? "wallpaper" : "white"
  function num(v, lo, hi, def) { var x = Number(v); return isFinite(x) ? Math.max(lo, Math.min(hi, x)) : def }
  function rgb(v, def) { var x = typeof v === "string" ? parseInt(v.replace(/^#|^0x/i, ""), 16) : Number(v); return isFinite(x) && x >= 0 && x <= 0xFFFFFF ? Math.floor(x) : def }
  o.width = Math.round(num(b.width, 1, 12, d.width))
  o.followWallpaper = b.followWallpaper === undefined ? d.followWallpaper : !!b.followWallpaper
  o.wallpaperMix = num(b.wallpaperMix, 0, 1, d.wallpaperMix)
  o.rimColor = rgb(b.rimColor, d.rimColor)
  o.rimStrength = num(b.rimStrength, 0, 1, d.rimStrength)
  o.glint = num(b.glint, 0, 1, d.glint)
  o.glintColor = rgb(b.glintColor, d.glintColor)
  o.glintLength = b.glintLength === "long" ? "long" : "short"
  o.seconds = num(b.seconds, 2, 60, d.seconds)
  o.sparkRate = Math.round(num(b.sparkRate, 2, 120, d.sparkRate))
  o.sparkSize = b.sparkSize === "small" || b.sparkSize === "large" ? b.sparkSize : "medium"
  o.sparkHold = Math.round(num(b.sparkHold, 0.15, 2, d.sparkHold) * 100) / 100
  var p = b.palette
  o.palette = p && /^[0-9a-f]{6}$/i.test(String(p.accent)) ? { accent: String(p.accent).toLowerCase(), base: /^[0-9a-f]{6}$/i.test(String(p.base)) ? String(p.base).toLowerCase() : String(p.accent).toLowerCase(), path: String(p.path || "") } : null
  return o
}

function rgbHex(n) { var h = (Number(n) >>> 0 & 0xFFFFFF).toString(16); while (h.length < 6) h = "0" + h; return h }
function mixHex(a, b, t) {
  var x = parseInt(a, 16), y = parseInt(b, 16), out = 0
  for (var s = 16; s >= 0; s -= 8) out = out * 256 + Math.round(((x >> s) & 255) * (1 - t) + ((y >> s) & 255) * t)
  return rgbHex(out)
}
function alphaHex(a) { var h = Math.round(Math.max(0, Math.min(1, a)) * 255).toString(16); return h.length < 2 ? "0" + h : h }

// The rim's two tones: from the wallpaper when following it, else rimColor.
function rimTones(b) {
  b = cleanBorder(b)
  if (b.followWallpaper && b.palette)
    return [mixHex("ffffff", b.palette.accent, b.wallpaperMix), mixHex("ffffff", b.palette.base, b.wallpaperMix)]
  var c = rgbHex(b.rimColor)
  return [c, mixHex(c, "ffffff", 0.35)]
}

// The glint's colour: its own, or a bright take on the wallpaper's accent.
// Kept close to white so it reads as light; the wallpaper's colour is
// stronger in the halo around it (haloHex).
function glintHex(b) {
  b = cleanBorder(b)
  if (b.sparkColor === "wallpaper" && b.palette) return mixHex("ffffff", b.palette.accent, 0.25)
  return rgbHex(b.glintColor)
}
function haloHex(b) {
  b = cleanBorder(b)
  if (b.sparkColor === "wallpaper" && b.palette) return mixHex("ffffff", b.palette.accent, 0.65)
  return mixHex(rgbHex(b.glintColor), rimTones(b)[0], 0.4)
}

// Ten stops (Hyprland's most) so a spark can be placed finely.
var STOPS = 10
function rimStops(b) {
  var t = rimTones(b), a = alphaHex(b.rimStrength), a2 = alphaHex(Math.min(1, b.rimStrength * 1.5))
  var r1 = "rgba(" + t[0] + a + ")", r2 = "rgba(" + t[1] + a2 + ")"
  return [r1, r2, r1, r1, r2, r1, r2, r1, r1, r2]
}

function borderColors(b) {
  b = cleanBorder(b)
  var t = rimTones(b), a = alphaHex(b.rimStrength), a2 = alphaHex(Math.min(1, b.rimStrength * 1.5))
  var r1 = "rgba(" + t[0] + a + ")", r2 = "rgba(" + t[1] + a2 + ")"
  var gh = glintHex(b)
  var g = "rgba(" + gh + alphaHex(b.glint) + ")"
  var e = "rgba(" + mixHex(gh, t[0], 0.5) + alphaHex(b.glint * 0.6) + ")"
  if (b.mode !== "travel") return rimStops(b)
  return b.glintLength === "long" ? [r1, r2, e, g, g, e, r2, r1] : [r1, r2, r1, g, e, r1, r2, r1]
}

// Sparkle: the rim with a spark centred at stop `pos` (0-9): a bright core
// (1, 3 or 5 stops for small/medium/large) and a halo on each side.
function sparkColors(b, pos) {
  b = cleanBorder(b)
  var stops = rimStops(b)
  var core = "rgba(" + glintHex(b) + alphaHex(b.glint) + ")"
  var halo = "rgba(" + haloHex(b) + alphaHex(Math.min(1, b.glint * 0.75)) + ")"
  var half = b.sparkSize === "small" ? 0 : b.sparkSize === "large" ? 2 : 1
  pos = Math.max(0, Math.min(STOPS - 1, pos))
  for (var i = pos - half - 1; i <= pos + half + 1; i++) {
    if (i < 0 || i >= STOPS) continue
    stops[i] = Math.abs(i - pos) <= half ? core : halo
  }
  return stops
}
function colorsLua(colors, angle) {
  return "hl.config({ general = { col = { active_border = { colors = { "
    + colors.map(function(c) { return "\"" + c + "\"" }).join(", ") + " }, angle = " + Math.round(angle) + " } } } })"
}

// Other windows: a fainter rim and no sparks, so the focused one stands out.
function inactiveColor(b) {
  b = cleanBorder(b)
  return "rgba(" + rimTones(b)[0] + alphaHex(b.rimStrength * 0.4) + ")"
}

function borderLua(b) {
  b = cleanBorder(b)
  if (b.style !== "glass") return ""
  return "hl.config({ general = { border_size = " + b.width + ", col = { active_border = { colors = { "
    + borderColors(b).map(function(c) { return "\"" + c + "\"" }).join(", ")
    + " }, angle = 45 }, inactive_border = \"" + inactiveColor(b) + "\" } } })\n"
    + (b.mode === "travel"
      ? "hl.animation({ leaf = \"borderangle\", enabled = true, speed = " + Math.round(b.seconds * 10) + ", bezier = \"linear\", style = \"loop\" })\n"
      : "hl.animation({ leaf = \"borderangle\", enabled = false })\n")
}

// ------------------------------------------------------------ see-through apps
// Per-app window opacity: { "<class>": [active, inactive] }. For apps with no
// transparency of their own (Dolphin), so the rest can stay fully opaque.
function cleanApps(map) {
  var out = {}
  for (var k in (map || {})) {
    if (!/^[A-Za-z0-9._-]{1,80}$/.test(k)) continue
    var v = map[k] || []
    var a = Number(v[0]), i = Number(v[1])
    if (!(a >= 0.3 && a <= 1)) continue
    if (!(i >= 0.3 && i <= 1)) i = a
    out[k] = [Math.round(a * 100) / 100, Math.round(i * 100) / 100]
  }
  return out
}
function appRuleLua(cls, a, i) {
  return "hl.window_rule({ match = { class = \"^(" + cls.replace(/\./g, "\\\\.") + ")$\" }, opacity = \"" + a + " " + i + "\" })"
}
function appsLua(map) {
  map = cleanApps(map)
  var out = []
  for (var k in map) out.push(appRuleLua(k, map[k][0], map[k][1]))
  return out.length ? out.join("\n") + "\n" : ""
}
