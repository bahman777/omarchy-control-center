import QtQuick
import qs.Commons
import qs.Ui

// [icon button] ———slider——— [chevron]   (GNOME quick settings slider row)
Item {
  id: row
  property string icon: ""
  property real value: 0
  property real to: 1
  property bool muted: false
  property bool hasMenu: false
  property bool expanded: false
  property string iconTip: ""
  property string menuTip: ""
  property string valueTip: ""
  // Keyboard: the slider is one stop; Left/Right adjust it.
  property bool ccFocusable: visible
  property bool hasCursor: false
  function ccActivate() { iconClicked() }
  function ccAdjust(dir) {
    var v = Math.max(0, Math.min(row.to, row.value + dir * 0.05))
    row.moved(v); row.committed(v)
    return true
  }
  signal iconClicked()
  signal moved(real value)
  signal committed(real value)
  signal menuRequested()

  width: parent ? parent.width : 300
  height: Style.space(40)

  QsRoundButton {
    id: btn
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    icon: row.icon
    tip: row.iconTip
    hasCursor: row.hasCursor
    ccFocusable: false
    onClicked: row.iconClicked()
  }
  PanelSlider {
    id: slider
    anchors.left: btn.right
    anchors.leftMargin: Style.space(10)
    anchors.right: chev.visible ? chev.left : parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    value: row.value
    minimum: 0
    maximum: row.to
    step: 0.01
    trackColor: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.15)
    fillColor: row.muted ? Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.4) : Color.accent
    knobColor: Color.menu.text
    onMoved: function(v) { row.moved(v) }
    onReleased: function(v) { row.committed(v) }
  }
  MouseArea {
    id: sliderHover
    anchors.fill: slider
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }
  PanelToolTip {
    visible: row.valueTip !== "" && (sliderHover.containsMouse || slider.dragging || row.hasCursor)
    text: row.valueTip
  }
  QsRoundButton {
    id: chev
    visible: row.hasMenu
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(32)
    icon: ""
    active: row.expanded
    rotation: row.expanded ? 90 : 0
    color: row.expanded ? Color.accent : "transparent"
    tip: row.menuTip
    onClicked: row.menuRequested()
  }
}
