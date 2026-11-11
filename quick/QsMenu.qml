import QtQuick
import qs.Commons

// The in-place menu a pill or slider chevron opens (GNOME quick settings menu).
Rectangle {
  id: menu
  property string icon: ""
  property string title: ""
  property bool active: true
  default property alias items: list.data

  width: parent ? parent.width : 300
  implicitHeight: col.implicitHeight + Style.space(20)
  height: implicitHeight
  radius: Style.cornerRadius > 0 ? Math.min(18, Style.space(18)) : 0
  color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.07)

  opacity: 0
  scale: 0.97
  Component.onCompleted: { opacity = 1; scale = 1 }
  Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
  Behavior on scale { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }

  Column {
    id: col
    x: Style.space(10)
    y: Style.space(10)
    width: parent.width - Style.space(20)
    spacing: Style.space(6)

    Row {
      visible: menu.title !== ""
      spacing: Style.space(10)
      leftPadding: Style.space(4)
      Rectangle {
        width: Style.space(32); height: width; radius: width / 2
        color: menu.active ? Color.accent : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.12)
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: menu.icon
          color: menu.active ? Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1) : Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.icon
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: menu.title
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
        font.weight: Font.DemiBold
      }
    }
    Column {
      id: list
      width: parent.width
      spacing: 0
    }
  }
}
