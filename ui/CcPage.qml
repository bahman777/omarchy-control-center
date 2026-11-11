import QtQuick
import QtQuick.Controls
import qs.Commons

// Scrolling page body: stacks CcGroups with GNOME-like spacing.
Flickable {
  id: root
  required property var cc
  default property alias content: col.data
  property int maxContentWidth: Style.space(720)

  clip: true
  contentWidth: width
  contentHeight: col.implicitHeight + Style.spacing.huge * 2
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

  Column {
    id: col
    width: Math.min(root.width - Style.spacing.huge * 2, root.maxContentWidth)
    x: Math.round((root.width - width) / 2)
    y: Style.spacing.huge
    spacing: Style.spacing.huge * 1.6
  }
}
