import QtQuick
import qs.Commons

// GNOME-style quick toggle pill: icon, title, subtitle; the body toggles,
// the chevron (when there is a menu) opens it in place below the row.
Rectangle {
  id: pill
  property string icon: ""
  property string title: ""
  property string subtitle: ""
  property bool active: false
  property bool hasMenu: false
  property bool menuOnly: false
  property bool expanded: false
  property bool busy: false
  signal toggled()
  signal menuRequested()

  readonly property color fg: Color.menu.text
  readonly property color ink: active ? Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1) : fg

  height: Style.space(54)
  radius: Style.cornerRadius > 0 ? height / 2 : 0
  color: active ? Color.accent
    : Qt.rgba(fg.r, fg.g, fg.b, bodyMouse.containsMouse || chevMouse.containsMouse ? 0.14 : 0.08)
  opacity: busy ? 0.7 : 1
  Behavior on color { ColorAnimation { duration: Style.duration(120) } }

  readonly property bool splitMenu: hasMenu && !menuOnly
  readonly property real chevWidth: splitMenu ? Style.space(40) : 0

  Item {
    id: body
    anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: pill.chevWidth }

    Text {
      id: glyph
      anchors.left: parent.left
      anchors.leftMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: pill.icon
      color: pill.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.iconLarge
      width: Style.space(22)
      horizontalAlignment: Text.AlignHCenter
    }
    Column {
      anchors.left: glyph.right
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: pill.title
        color: pill.ink
        elide: Text.ElideRight
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }
      Text {
        width: parent.width
        visible: pill.subtitle !== ""
        textFormat: Text.PlainText
        text: pill.subtitle
        color: Qt.rgba(pill.ink.r, pill.ink.g, pill.ink.b, 0.75)
        elide: Text.ElideRight
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.caption
      }
    }
    MouseArea {
      id: bodyMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: !pill.busy
      onClicked: pill.menuOnly ? pill.menuRequested() : pill.toggled()
    }
  }

  Item {
    visible: pill.splitMenu
    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
    width: pill.chevWidth
    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 1; height: parent.height * 0.5
      color: Qt.rgba(pill.ink.r, pill.ink.g, pill.ink.b, 0.25)
    }
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: ""
      rotation: pill.expanded ? 90 : 0
      Behavior on rotation { NumberAnimation { duration: Style.duration(150); easing.type: Easing.OutCubic } }
      color: pill.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: chevMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.menuRequested()
    }
  }
}
