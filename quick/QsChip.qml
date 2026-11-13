import QtQuick
import qs.Commons
import qs.Ui

// Small round toggle with a label underneath, for the less-used quick
// toggles. Click toggles (or opens the menu when the toggle has no on/off of
// its own); right-click opens the menu when there is one.
Item {
  id: chip
  property string icon: ""
  property string label: ""
  property bool active: false
  property bool hasMenu: false
  property bool menuOnly: false
  property bool expanded: false
  property string tip: ""
  signal toggled()
  signal menuRequested()

  // Keyboard cursor contract (see QuickContent.moveCursor).
  property bool ccFocusable: visible
  property bool hasCursor: false
  function ccActivate() { menuOnly ? menuRequested() : toggled() }

  readonly property color fg: Color.menu.text
  implicitHeight: circle.height + Style.space(4) + caption.implicitHeight

  Rectangle {
    id: circle
    anchors.horizontalCenter: parent.horizontalCenter
    width: Style.space(46); height: width
    radius: Style.cornerRadius > 0 ? width / 2 : 0
    color: chip.active ? Color.accent : Qt.rgba(chip.fg.r, chip.fg.g, chip.fg.b, mouse.containsMouse ? 0.16 : 0.08)
    border.width: chip.hasCursor || chip.expanded ? 2 : 0
    border.color: chip.active ? chip.fg : Color.accent
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.icon
      color: chip.active ? Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1) : chip.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.icon
    }
    // A small notch says "right-click for more".
    Rectangle {
      visible: chip.hasMenu && !chip.menuOnly
      width: Style.space(6); height: width; radius: width / 2
      anchors { right: parent.right; bottom: parent.bottom; rightMargin: Style.space(3); bottomMargin: Style.space(3) }
      color: chip.active ? Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 0.6) : Qt.rgba(chip.fg.r, chip.fg.g, chip.fg.b, 0.4)
    }
  }
  Text {
    id: caption
    anchors.top: circle.bottom
    anchors.topMargin: Style.space(4)
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: chip.label
    color: Qt.rgba(chip.fg.r, chip.fg.g, chip.fg.b, 0.85)
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.bodySmall
  }
  MouseArea {
    id: mouse
    anchors.fill: circle
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(m) {
      if (m.button === Qt.RightButton) { if (chip.hasMenu) chip.menuRequested() }
      else chip.ccActivate()
    }
  }
  PanelToolTip { visible: chip.tip !== "" && (mouse.containsMouse || chip.hasCursor); text: chip.tip }
}
