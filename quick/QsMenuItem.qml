import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: item
  property string icon: ""
  property string text: ""
  property string detail: ""
  property string trailing: ""
  property bool checked: false
  property bool dim: false
  property bool separatorAbove: false
  property bool clickable: true
  property string tip: ""
  signal clicked()
  property bool ccFocusable: visible && clickable
  property bool hasCursor: false
  function ccActivate() { clicked() }

  width: parent ? parent.width : 280
  height: Style.space(detail !== "" ? 44 : 36) + (separatorAbove ? Style.space(9) : 0)
  radius: Style.cornerRadius > 0 ? Style.space(10) : 0
  color: "transparent"

  Rectangle {
    visible: item.separatorAbove
    x: Style.space(8); width: parent.width - Style.space(16); height: 1
    y: Style.space(4)
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.12)
  }

  Rectangle {
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    height: parent.height - (item.separatorAbove ? Style.space(9) : 0)
    radius: item.radius
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, (mouse.containsMouse || item.hasCursor) && item.clickable ? 0.10 : 0)
    border.width: item.hasCursor ? 2 : 0
    border.color: Color.accent

    Text {
      id: ic
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: item.icon !== "" ? Style.space(20) : 0
      textFormat: Text.PlainText
      text: item.icon
      color: Color.menu.text
      opacity: item.dim ? 0.5 : 1
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
      horizontalAlignment: Text.AlignHCenter
    }
    Column {
      anchors.left: ic.right
      anchors.leftMargin: item.icon !== "" ? Style.space(10) : 0
      anchors.right: tail.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      opacity: item.dim ? 0.55 : 1
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: item.text
        elide: Text.ElideRight
        color: Color.menu.text
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
      }
      Text {
        width: parent.width
        visible: item.detail !== ""
        textFormat: Text.PlainText
        text: item.detail
        elide: Text.ElideRight
        color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.6)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
    Text {
      id: tail
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: item.checked ? "" : item.trailing
      color: item.checked ? Color.accent : Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.6)
      font.family: Style.font.family
      font.pixelSize: item.checked ? Style.font.body : Style.font.caption
    }
    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: item.clickable
      cursorShape: Qt.PointingHandCursor
      onClicked: item.clicked()
    }
    PanelToolTip { visible: item.tip !== "" && (mouse.containsMouse || item.hasCursor); text: item.tip }
  }
}
