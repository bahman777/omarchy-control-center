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

  ccFocusable: visible
  function optValue(o) { return typeof o === "object" ? String(o.value) : String(o) }
  function ccActivate() {
    if (useDropdown) { dd.forceActiveFocus(); dd.open() }
    else ccAdjust(1)
  }
  function ccAdjust(dir) {
    if (useDropdown || options.length === 0) return false
    var idx = 0
    for (var i = 0; i < options.length; i++) if (optValue(options[i]) === value) idx = i
    idx = Math.max(0, Math.min(options.length - 1, idx + dir))
    if (optValue(options[idx]) !== value) picked(optValue(options[idx]))
    return true
  }

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
    id: dd
    visible: root.useDropdown
    hasCursor: root.hasCursor
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
