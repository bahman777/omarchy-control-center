import QtQuick
import qs.Commons

// Small horizontal level meter (battery and similar), 0..1.
Item {
  id: bar
  property real level: 0
  property bool low: level <= 0.15
  implicitWidth: Style.space(110)
  implicitHeight: Style.space(8)
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.14)
  }
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(height, parent.width * Math.max(0, Math.min(1, bar.level)))
    radius: height / 2
    color: bar.low ? Color.urgent : Color.accent
  }
}
