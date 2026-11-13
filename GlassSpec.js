.pragma library

// hyprglass (github.com/hyprnux/hyprglass) settings the Glass page edits:
// label, plain-language help, range and the plugin's own default. Types:
// "float", "int", "color" (0xRRGGBBAA, alpha = strength) and "bool".
var GROUPS = [
  { id: "glass", title: "Glass", subtitle: "The body of the glass behind each window" },
  { id: "edge", title: "Edge & lens", subtitle: "How the rim bends and catches light" },
  { id: "bevel", title: "Bevel & light", subtitle: "The lit line along the edge and where light comes from" },
  { id: "color", title: "Colour", subtitle: "How what's behind the glass is toned" },
  { id: "more", title: "More", subtitle: "Frost, grain and special effects" }
]

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
