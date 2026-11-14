import QtQuick
import qs.Commons
import qs.Ui
import "../ui"

// [icon button] ———slider——— [chevron]   (GNOME quick settings slider row)
Item {
  id: row
  property string icon: ""
  property real value: 0
  property real to: 1
  property bool muted: false
  property bool hasMenu: false
  property bool expanded: false
  property string iconTip: ""
  property string menuTip: ""
  property string valueTip: ""
  // Keyboard: the slider is one stop; Left/Right adjust it.
  property bool ccFocusable: visible
  property bool hasCursor: false
  function ccActivate() { iconClicked() }
  function ccAdjust(dir) {
    var v = Math.max(0, Math.min(row.to, row.value + dir * 0.05))
    row.moved(v); row.committed(v)
    return true
  }
  signal iconClicked()
  signal moved(real value)
  signal committed(real value)
  signal menuRequested()

  width: parent ? parent.width : 300
  height: Style.space(40)

  QsRoundButton {
    id: btn
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    icon: row.icon
    tip: row.iconTip
    hasCursor: row.hasCursor
    ccFocusable: false
    onClicked: row.iconClicked()
  }
  PanelSlider {
    id: slider
    anchors.left: btn.right
    anchors.leftMargin: Style.space(10)
    anchors.right: chev.visible ? chev.left : parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    value: row.value
    minimum: 0
    maximum: row.to
    step: 0.01
    // Drawn here instead (glass groove, fill and knob); the slider's own
    // parts stay for input only.
    trackColor: "transparent"
    fillColor: "transparent"
    knobColor: "transparent"
    trackHeight: Style.space(8)
    knobSize: Style.space(20)
    onMoved: function(v) { row.moved(v) }
    onReleased: function(v) { row.committed(v) }
    WheelScroll {}

    readonly property color fillTint: row.muted ? Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.4) : Color.accent
    readonly property real grooveX: knobSize / 2
    readonly property real grooveW: width - knobSize
    // Groove: recessed, darker at the top.
    Rectangle {
      x: slider.grooveX; width: slider.grooveW
      anchors.verticalCenter: parent.verticalCenter
      height: slider.trackHeight; radius: height / 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
        GradientStop { position: 1.0; color: Qt.rgba(Color.menu.text.r, Color.menu.text.g, Color.menu.text.b, 0.12) }
      }
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.18)
    }
    // Fill: the accent with a glass sheen.
    Rectangle {
      x: slider.grooveX
      width: Math.max(height, slider.grooveW * slider.progress)
      anchors.verticalCenter: parent.verticalCenter
      height: slider.trackHeight; radius: height / 2
      color: slider.fillTint
      Behavior on width { enabled: !slider.dragging; NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
      Glass { strong: true }
    }
    // Knob: raised, light, with a shadow.
    Rectangle {
      width: slider.knobSize; height: width; radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      x: slider.grooveX + slider.grooveW * slider.progress - width / 2
      scale: slider.dragging ? 1.12 : 1
      Behavior on x { enabled: !slider.dragging; NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: Style.duration(110); easing.type: Easing.OutCubic } }
      GlassShadow { depth: 2 }
      gradient: Gradient {
        GradientStop { position: 0.0; color: "#ffffff" }
        GradientStop { position: 1.0; color: "#d3d8de" }
      }
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.18)
    }
  }
  MouseArea {
    id: sliderHover
    anchors.fill: slider
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }
  PanelToolTip {
    visible: row.valueTip !== "" && (sliderHover.containsMouse || slider.dragging || row.hasCursor)
    text: row.valueTip
  }
  QsRoundButton {
    id: chev
    visible: row.hasMenu
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(32)
    icon: ""
    active: row.expanded
    rotation: row.expanded ? 90 : 0
    color: row.expanded ? Color.accent : "transparent"
    tip: row.menuTip
    onClicked: row.menuRequested()
  }
}
