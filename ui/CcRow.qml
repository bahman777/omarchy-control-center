import QtQuick
import qs.Commons

// One row in a CcGroup: optional icon, title, subtitle, and trailing controls.
Item {
  id: row
  property string icon: ""
  property color iconColor: Color.menu.text
  property string title: ""
  property string subtitle: ""
  property color subtitleColor: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
  property bool clickable: false
  property bool selected: false
  property bool dim: false
  property bool chevron: false
  // Hairline above the row; off for the first row of a group.
  property bool separator: !row.Positioner.isFirstItem
  default property alias trailing: trail.data
  signal clicked()
  signal rightClicked()

  width: parent ? parent.width : 300
  implicitHeight: Math.max(Style.space(50), texts.implicitHeight + Style.space(18))
  height: implicitHeight
  opacity: dim ? 0.55 : 1

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b,
                   row.selected ? 0.09 : (mouse.containsMouse && row.clickable ? 0.06 : 0))
  }

  Rectangle {
    visible: row.separator
    anchors { top: parent.top; left: parent.left; right: parent.right }
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.rowPaddingX
    height: 1
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.08)
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: row.clickable
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(m) { if (m.button === Qt.RightButton) row.rightClicked(); else row.clicked() }
  }

  CcIcon {
    id: ic
    visible: row.icon !== ""
    glyph: row.icon
    color: row.iconColor
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.verticalCenter: parent.verticalCenter
  }

  Column {
    id: texts
    anchors.left: ic.visible ? ic.right : parent.left
    anchors.leftMargin: ic.visible ? Style.spacing.lg : Style.spacing.rowPaddingX
    anchors.right: trail.left
    anchors.rightMargin: Style.spacing.lg
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xxs
    CcText {
      width: parent.width
      text: row.title
      font.pixelSize: Style.font.subtitle
    }
    CcText {
      width: parent.width
      visible: row.subtitle !== ""
      text: row.subtitle
      color: row.subtitleColor
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
      maximumLineCount: 3
    }
  }

  Row {
    id: trail
    anchors.right: chev.visible ? chev.left : parent.right
    anchors.rightMargin: chev.visible ? Style.spacing.sm : Style.spacing.rowPaddingX
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.lg
    layoutDirection: Qt.LeftToRight
  }

  CcText {
    id: chev
    visible: row.chevron
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.rowPaddingX
    anchors.verticalCenter: parent.verticalCenter
    text: ""
    color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.62)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
