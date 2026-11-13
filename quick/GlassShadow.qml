import QtQuick

// Soft drop shadow under a shape: add it as a direct child of the shape; its
// negative z draws it behind the shape itself.
Item {
  id: s
  property real radius: parent ? parent.radius : 0
  property real depth: 2
  z: -1
  anchors.fill: parent

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: s.depth + 1
    anchors.bottomMargin: -s.depth - 1
    anchors.leftMargin: 1
    anchors.rightMargin: 1
    radius: s.radius
    color: Qt.rgba(0, 0, 0, 0.16)
  }
  Rectangle {
    anchors.fill: parent
    anchors.topMargin: s.depth
    anchors.bottomMargin: -s.depth
    radius: s.radius
    color: Qt.rgba(0, 0, 0, 0.12)
  }
}
