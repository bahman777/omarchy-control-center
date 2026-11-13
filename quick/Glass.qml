import QtQuick

// Glass sheen over a filled shape: lighter at the top, a touch darker at the
// bottom, a fine rim, and a bright line along the top edge. Add it as the
// shape's FIRST child so its contents draw over it. `strong` for
// accent-filled (active) shapes, which carry more light.
Item {
  id: g
  property real radius: parent ? parent.radius : 0
  property bool strong: false
  anchors.fill: parent

  Rectangle {
    anchors.fill: parent
    radius: g.radius
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, g.strong ? 0.30 : 0.11) }
      GradientStop { position: 0.48; color: Qt.rgba(1, 1, 1, g.strong ? 0.06 : 0.02) }
      GradientStop { position: 0.52; color: Qt.rgba(0, 0, 0, 0.0) }
      GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, g.strong ? 0.16 : 0.14) }
    }
  }
  Rectangle {
    anchors.fill: parent
    radius: g.radius
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, g.strong ? 0.22 : 0.09)
  }
  // Highlight along the top edge, kept inside the rounded corners.
  Rectangle {
    x: Math.min(g.radius, g.width / 2) * 0.8
    width: g.width - 2 * x
    y: 1
    height: 1
    color: Qt.rgba(1, 1, 1, g.strong ? 0.55 : 0.22)
  }
}
