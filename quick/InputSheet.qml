import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// A small dialog over the whole panel for anything you have to type (a Wi-Fi
// password, for one). It dims the panel, sits in the middle where it can't be
// scrolled out of sight, and takes the keyboard: Enter confirms, Esc cancels.
// Open it with ask({ title, subtitle, placeholder, password, okText, value },
// function(text) {...}); BarWidget exposes it as cc.ask().
Item {
  id: sheet
  anchors.fill: parent
  visible: opened
  z: 1000

  property bool opened: false
  property string title: ""
  property string subtitle: ""
  property string placeholder: ""
  property string okText: "OK"
  property bool password: false
  property bool reveal: false
  property var onAccept: null
  // Called after it closes, to hand the keyboard back to the panel.
  property var restoreFocus: null

  readonly property color fg: Color.menu.text

  function ask(opts, cb) {
    opts = opts || {}
    title = String(opts.title || "")
    subtitle = String(opts.subtitle || "")
    placeholder = String(opts.placeholder || "")
    okText = String(opts.okText || "OK")
    password = !!opts.password
    reveal = false
    onAccept = cb || null
    field.text = String(opts.value || "")
    opened = true
    Qt.callLater(function() { field.forceActiveFocus(); field.selectAll() })
  }
  function close() {
    opened = false
    field.text = ""
    onAccept = null
    field.focus = false
    if (restoreFocus) restoreFocus()
  }
  function cancel() { close() }
  function accept() {
    var t = field.text, cb = onAccept
    if (t === "") return
    close()
    if (cb) cb(t)
  }

  // Dim the panel; a click outside the card cancels.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)
    MouseArea { anchors.fill: parent; onClicked: sheet.cancel() }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(32), Style.space(420))
    height: col.implicitHeight + Style.space(36)
    radius: Style.cornerRadius > 0 ? Style.space(16) : 0
    color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1)
    border.width: 1
    border.color: Qt.rgba(sheet.fg.r, sheet.fg.g, sheet.fg.b, 0.18)
    GlassShadow { depth: 4 }
    Glass {}
    MouseArea { anchors.fill: parent }  // clicks on the card don't cancel

    opacity: sheet.opened ? 1 : 0
    scale: sheet.opened ? 1 : 0.96
    Behavior on opacity { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic } }

    Column {
      id: col
      x: Style.space(18); y: Style.space(18)
      width: parent.width - Style.space(36)
      spacing: Style.space(10)

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: sheet.title
        color: sheet.fg
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.subtitle
        font.weight: Font.DemiBold
      }
      Text {
        width: parent.width
        visible: sheet.subtitle !== ""
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: sheet.subtitle
        color: Qt.rgba(sheet.fg.r, sheet.fg.g, sheet.fg.b, 0.65)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }
      Row {
        width: parent.width
        spacing: Style.space(8)
        TextField {
          id: field
          width: parent.width - (showBtn.visible ? showBtn.width + parent.spacing : 0)
          password: sheet.password && !sheet.reveal
          placeholderText: sheet.placeholder
          foreground: sheet.fg
          Keys.onReturnPressed: sheet.accept()
          Keys.onEnterPressed: sheet.accept()
          Keys.onEscapePressed: function(event) { event.accepted = true; sheet.cancel() }
        }
        Button {
          id: showBtn
          visible: sheet.password
          anchors.verticalCenter: field.verticalCenter
          text: sheet.reveal ? "Hide" : "Show"
          bordered: true
          foreground: sheet.fg
          fontSize: Style.font.bodySmall
          onClicked: { sheet.reveal = !sheet.reveal; field.forceActiveFocus() }
        }
      }
      Row {
        anchors.right: parent.right
        spacing: Style.space(8)
        Button {
          text: "Cancel"
          bordered: true
          foreground: sheet.fg
          fontSize: Style.font.bodySmall
          onClicked: sheet.cancel()
        }
        Button {
          text: sheet.okText
          bordered: true
          foreground: sheet.fg
          fontSize: Style.font.bodySmall
          enabled: field.text !== ""
          opacity: enabled ? 1 : 0.5
          onClicked: sheet.accept()
        }
      }
    }
  }
}
