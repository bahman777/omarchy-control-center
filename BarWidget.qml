import QtQuick
import qs.Ui
import qs.Commons

// Gear in the bar. Left click toggles the Control Center window; right click
// opens it straight on the Wi-Fi page.
BarWidget {
  id: root
  moduleName: "io.github.bahman777.control-center"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function openPage(page) {
    if (!root.bar || !root.bar.shell) return
    var payload = page ? JSON.stringify({ page: page }) : "{}"
    if (page) root.bar.shell.summon(root.moduleName, payload)
    else root.bar.shell.toggle(root.moduleName, payload)
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: "Control Center"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openPage("wifi")
      else root.openPage("")
    }
  }
}
