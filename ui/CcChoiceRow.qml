import QtQuick
import qs.Commons
import qs.Ui

// Row with a segmented "pick one" control (short lists) or a dropdown (long).
CcRow {
  id: root
  property var options: []
  property string value: ""
  property bool useDropdown: options.length > 4
  property int dropdownWidth: Style.space(220)
  signal picked(string value)

  ButtonGroup {
    visible: !root.useDropdown
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    options: root.options
    value: root.value
    foreground: Color.menu.text
    background: Color.menu.background
    fontFamily: Style.font.menuFamily
    fontSize: Style.font.bodySmall
    onChanged: function(v) { root.picked(v) }
  }
  Dropdown {
    visible: root.useDropdown
    width: root.dropdownWidth
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    showLabel: false
    options: root.options
    value: root.value
    foreground: Color.menu.text
    fontFamily: Style.font.menuFamily
    onChanged: function(v) { root.picked(v) }
  }
}
