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
    onClicked: row.iconClicked()
  }
  PanelSlider {
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
    onClicked: row.menuRequested()
  }
}
