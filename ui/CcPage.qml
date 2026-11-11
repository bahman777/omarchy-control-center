import QtQuick
import QtQuick.Controls
import qs.Commons

// Scrolling page body: stacks CcGroups with GNOME-like spacing.
Flickable {
  id: root
  required property var cc
  default property alias content: col.data
  property int maxContentWidth: Style.space(720)
  // Inside the quick panel the page is as tall as its content and the panel
  // scrolls; on its own it scrolls itself.
  implicitHeight: contentHeight
  interactive: contentHeight > height

  clip: true
  contentWidth: width
  contentHeight: col.implicitHeight + Style.spacing.md + Style.spacing.huge
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.VerticalFlick
  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

  Column {
    id: col
    width: Math.min(root.width - Style.spacing.lg * 2, root.maxContentWidth)
    x: Math.round((root.width - width) / 2)
    y: Style.spacing.md
    spacing: Style.spacing.huge * 1.6
  }
}
