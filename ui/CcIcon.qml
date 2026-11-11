import QtQuick
import qs.Commons

// Nerd Font glyph in a fixed square, so rows line up whatever the glyph width.
Item {
  id: root
  property string glyph: ""
  property color color: Color.menu.text
  property real size: Style.font.iconLarge
  implicitWidth: Math.round(size * 1.5)
  implicitHeight: implicitWidth
  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.glyph
    color: root.color
    font.family: Style.font.family
    font.pixelSize: root.size
  }
}
