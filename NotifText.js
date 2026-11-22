.pragma library

// Notification text. The spec's body markup is a tiny HTML subset: <b>, <i>,
// <u>, <a href>, <img>, and &amp;-style entities. We show <b>, <i> and <u>
// (and line breaks) and nothing else: every other tag is dropped but its
// text kept (a link becomes its words, never something clickable), and all
// text is escaped before it reaches Qt's StyledText, so no sender can make
// it render a link, an image or anything else.

// Only real HTML tag names count as tags (no space after "<"), so text like
// "x < y > z", "press <Enter>" or "<john@example.com>" is left alone.
var TAG = /<(\/?)(b|i|u|s|a|img|br|p|span|div|font|strong|em|big|small|tt|code|pre|sub|sup|ul|ol|li|h[1-6]|hr|blockquote)(\s[^<>]*)?\/?>/gi

function decode(s) {
  return String(s).replace(/&(#x[0-9a-fA-F]{1,6}|#[0-9]{1,7}|amp|lt|gt|quot|apos|nbsp);/g, function(all, e) {
    if (e === "amp") return "&"
    if (e === "lt") return "<"
    if (e === "gt") return ">"
    if (e === "quot") return "\""
    if (e === "apos") return "'"
    if (e === "nbsp") return " "
    var n = e.charAt(1) === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)
    if (!(n > 0 && n <= 0x10FFFF) || (n >= 0xD800 && n <= 0xDFFF)) return all
    return String.fromCodePoint(n)
  })
}

function escape(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// Plain text: tags removed (<br> becomes a line break), entities decoded.
function plain(s) {
  s = String(s || "")
  return decode(s.replace(TAG, function(all, close, name) {
    return name.toLowerCase() === "br" ? "\n" : ""
  }))
}

// StyledText for display: only b/i/u survive, balanced; text escaped.
function rich(s) {
  s = String(s || "")
  var out = "", last = 0, open = { b: 0, i: 0, u: 0 }, m
  TAG.lastIndex = 0
  while ((m = TAG.exec(s)) !== null) {
    out += escape(decode(s.slice(last, m.index)))
    last = TAG.lastIndex
    var name = m[2].toLowerCase(), closing = m[1] === "/"
    if (name === "br") { out += "<br>"; continue }
    if (name === "strong") name = "b"
    if (name === "em") name = "i"
    if (name !== "b" && name !== "i" && name !== "u") continue
    if (closing) { if (open[name] > 0) { open[name]--; out += "</" + name + ">" } }
    else { open[name]++; out += "<" + name + ">" }
  }
  out += escape(decode(s.slice(last)))
  ;["u", "i", "b"].forEach(function(t) { while (open[t]-- > 0) out += "</" + t + ">" })
  return out.replace(/\r?\n/g, "<br>")
}
