import QtQuick

// Laid over a slider: the mouse wheel scrolls the page instead of changing
// the value (Omarchy's slider takes wheel steps, so scrolling a long panel
// kept moving whatever slider passed under the pointer). Clicks and drags
// aren't accepted here, so they still reach the slider. The wheel goes to the
// nearest enclosing Flickable that can actually scroll.
MouseArea {
  anchors.fill: parent
  z: 100
  acceptedButtons: Qt.NoButton
  onWheel: function(wheel) {
    var f = parent
    while (f && !(typeof f.flick === "function" && f.contentHeight > f.height + 1)) f = f.parent
    if (!f) return  // nothing to scroll: swallow it rather than move the slider
    var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * 64
    f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY - dy))
  }
}
