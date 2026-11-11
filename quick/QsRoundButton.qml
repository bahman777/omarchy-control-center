import QtQuick
import qs.Commons

Rectangle {
  id: b
  property string icon: ""
  property bool active: false
  signal clicked()
  width: Style.space(38); height: width; radius: Style.cornerRadius > 0 ? width / 2 : 0
  color: active ? Color.accent : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, mouse.containsMouse ? 0.16 : 0.08)
  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: b.icon
    color: b.active ? Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1) : Color.menu.text
    font.family: Style.font.family
    font.pixelSize: Style.font.icon
  }
  MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}
