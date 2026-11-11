import QtQuick
import qs.Commons

// A titled, rounded "boxed list" of rows, like a GNOME Settings group.
Column {
  id: root
  property string title: ""
  property string subtitle: ""
  default property alias rows: box.data
  property alias header: headerSlot.data

  width: parent ? parent.width : 400
  spacing: Style.spacing.md

  Item {
    width: root.width
    height: Math.max(titleCol.implicitHeight, headerSlot.childrenRect.height)
    visible: root.title !== "" || root.subtitle !== "" || headerSlot.children.length > 0
    Column {
      id: titleCol
      anchors.left: parent.left
      anchors.right: headerSlot.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xxs
      CcText {
        width: parent.width
        visible: root.title !== ""
        text: root.title
        font.pixelSize: Style.font.subtitle
        font.weight: Font.DemiBold
      }
      CcText {
        width: parent.width
        visible: root.subtitle !== ""
        text: root.subtitle
        color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
      }
    }
    Row {
      id: headerSlot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.md
    }
  }

  Rectangle {
    width: root.width
    height: box.implicitHeight
    visible: box.children.length > 0
    radius: Math.max(8, Style.cornerRadius)
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.045)
    border.width: 1
    border.color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.10)
    clip: true
    Column { id: box; width: parent.width }
  }
}
