import QtQuick
import qs.Ui

// Row with an on/off switch; the whole row toggles.
CcRow {
  id: root
  property bool checked: false
  property bool busy: false
  signal toggled()
  clickable: !busy
  ccFocusable: visible
  onClicked: root.toggled()

  ToggleSwitch {
    checked: root.checked
    busy: root.busy
    interactive: false
    hasCursor: root.hasCursor
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  }
}
