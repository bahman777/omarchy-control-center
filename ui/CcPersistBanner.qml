import QtQuick
import qs.Commons

// Shown while Hyprland changes are live but would be lost on the next login:
// keeping them needs one line in hyprland.lua, which is only added on request.
CcGroup {
  id: root
  required property var hypr
  visible: hypr.sessionOnly
  CcRow {
    icon: "\uf05a"
    iconColor: Color.accent
    title: "Changes are active until you log out"
    subtitle: "To keep them, the Control Center adds one line to ~/.config/hypr/hyprland.lua that loads ~/.config/hypr/control-center.lua (a backup is made first)."
    CcButton { text: "Keep after restart"; onClicked: root.hypr.installInclude() }
  }
}
