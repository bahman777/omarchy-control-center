import QtQuick
import qs.Commons
import qs.Ui

// Row with a slider and a live value readout. `moved` fires while dragging,
// `committed` once on release.
CcRow {
  id: root
  property real value: 0
  property real from: 0
  property real to: 1
  property real stepSize: 0.05
  property bool integer: false
  property string valueText: ""
  forceStack: width < Style.space(560)
  autoStack: false
  property int sliderWidth: stacked ? Math.max(Style.space(120), width - (icon !== "" ? Style.space(48) : 0) - Style.spacing.rowPaddingX * 2 - Style.space(46) - Style.spacing.lg) : Style.space(240)
  ccFocusable: visible
  function ccActivate() {}
  function ccAdjust(dir) {
    var span = to - from
    var step = Math.max(stepSize, span / 20)
    var v = Math.max(from, Math.min(to, value + dir * step))
    if (integer) v = Math.round(v)
    moved(v); committed(v)
    return true
  }
  // Follows the knob while dragging, for live value readouts.
  readonly property real current: slider.liveValue
  signal moved(real value)
  signal committed(real value)

  Item {
    width: root.sliderWidth
    height: Style.spacing.controlHeight
    PanelSlider {
      id: slider
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      value: root.value
      minimum: root.from
      maximum: root.to
      step: root.stepSize
      integer: root.integer
      trackColor: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.15)
      fillColor: Color.accent
      knobColor: Color.menu.text
      tickColor: Color.menu.background
      onMoved: function(v) { root.moved(v) }
      onReleased: function(v) { root.committed(v) }
      WheelScroll {}
    }
  }
  CcText {
    width: Style.space(46)
    horizontalAlignment: Text.AlignRight
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    text: root.valueText
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
    font.pixelSize: Style.font.bodySmall
  }
}
