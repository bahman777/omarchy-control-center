import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui

// One notification: icon or image, app and time, summary, body, action
// buttons, inline reply and a close button. `row` is a plain snapshot (see
// NotifyService.rows); every action goes back through `svc` by id, so a card
// never holds the live Notification object.
Rectangle {
  id: card
  required property var row
  required property var svc
  property bool compact: false
  property bool popup: false
  property bool showReply: row.hasReply && !popup
  property bool replying: false

  // Keyboard cursor: the card itself runs its default action.
  property bool ccFocusable: visible
  property bool hasCursor: false
  function ccActivate() { svc.activate(row.id) }

  readonly property color fg: popup ? Color.popups.text : Color.menu.text
  readonly property bool critical: row.urgency === 2

  width: parent ? parent.width : Style.space(380)
  implicitHeight: content.implicitHeight + Style.space(24)
  height: implicitHeight
  radius: Style.cornerRadius > 0 ? Style.space(14) : 0
  color: popup
    ? Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, Math.max(0.96, Color.popups.background.a))
    : Qt.rgba(fg.r, fg.g, fg.b, hover.containsMouse || hasCursor ? 0.10 : 0.06)
  border.width: hasCursor ? 2 : (popup ? 1 : 0)
  border.color: hasCursor ? Color.accent : (critical ? Color.urgent : Color.popups.border)

  function ago(ms) {
    var s = Math.max(0, Math.round((Date.now() - ms) / 1000))
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + " min"
    if (s < 86400) return Math.floor(s / 3600) + " h"
    return Qt.formatDateTime(new Date(ms), "MMM d")
  }
  property int tick: 0
  Timer { interval: 30000; running: true; repeat: true; onTriggered: card.tick++ }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: card.row.hasDefault ? Qt.PointingHandCursor : Qt.ArrowCursor
    onContainsMouseChanged: if (card.popup) card.svc.hover(card.row.id, containsMouse)
    onClicked: card.svc.activate(card.row.id)
  }

  Column {
    id: content
    x: Style.space(12)
    y: Style.space(12)
    width: parent.width - Style.space(24)
    spacing: Style.space(6)

    Item {
      width: parent.width
      height: Math.max(iconBox.height, textCol.implicitHeight)

      Item {
        id: iconBox
        width: Style.space(card.compact ? 32 : 40)
        height: width
        IconImage {
          id: img
          anchors.fill: parent
          visible: status === Image.Ready
          // The app icon is a theme name or, from some apps, a file.
          readonly property string appIcon: card.row.appIcon || ""
          source: card.row.image !== "" ? card.row.image
            : appIcon.charAt(0) === "/" ? "file://" + appIcon.split("/").map(encodeURIComponent).join("/")
            : appIcon.indexOf("file://") === 0 ? appIcon
            : appIcon !== "" ? Quickshell.iconPath(appIcon, true) : ""
          asynchronous: true
        }
        Text {
          anchors.centerIn: parent
          visible: !img.visible
          textFormat: Text.PlainText
          text: String.fromCodePoint(0xF009A)
          color: card.critical ? Color.urgent : Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.iconLarge
        }
      }

      Column {
        id: textCol
        anchors.left: iconBox.right
        anchors.leftMargin: Style.space(10)
        anchors.right: closeBtn.left
        anchors.rightMargin: Style.space(6)
        spacing: Style.space(2)
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: (card.row.appName || "Notification") + "  ·  " + (card.tick, card.ago(card.row.time))
          color: Qt.rgba(card.fg.r, card.fg.g, card.fg.b, 0.6)
          elide: Text.ElideRight
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: card.row.summary
          color: card.fg
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }
        Text {
          width: parent.width
          visible: card.row.body !== ""
          // Already sanitised by NotifText.rich: only <b>, <i>, <u>, <br>.
          textFormat: Text.StyledText
          text: card.row.bodyRich || ""
          color: Qt.rgba(card.fg.r, card.fg.g, card.fg.b, 0.85)
          wrapMode: Text.Wrap
          maximumLineCount: card.compact ? 3 : 8
          elide: Text.ElideRight
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      QsRoundButton {
        id: closeBtn
        anchors.right: parent.right
        anchors.top: parent.top
        width: Style.space(26)
        icon: String.fromCodePoint(0xF0156)
        tip: card.popup ? "Dismiss" : "Remove"
        onClicked: card.svc.dismiss(card.row.id)
      }
    }

    Flow {
      width: parent.width
      visible: card.row.actions.length > 0 || (card.popup && card.row.hasReply)
      spacing: Style.space(6)
      leftPadding: iconBox.width + Style.space(10)
      Button {
        visible: card.popup && card.row.hasReply
        text: "Reply…"
        bordered: true
        foreground: card.fg
        fontSize: Style.font.bodySmall
        onClicked: { card.svc.hidePopup(card.row.id); Quickshell.execDetached(["omarchy-shell", "control-center", "settings", "notifications"]) }
      }
      Repeater {
        model: card.row.actions
        delegate: Button {
          required property var modelData
          text: modelData.text
          bordered: true
          foreground: card.fg
          fontSize: Style.font.bodySmall
          property bool ccFocusable: visible
          function ccActivate() { clicked() }
          onClicked: card.svc.invoke(card.row.id, modelData.id)
        }
      }
    }

    // The reply field exists only once you choose to reply (a Loader): an
    // editable field kept around hidden on every card (pop-ups included) can
    // be asked about the clipboard on some Qt Wayland builds and stall the
    // shell. Sending or Esc puts the Reply button back.
    Button {
      visible: card.showReply && !card.replying
      x: iconBox.width + Style.space(10)
      text: "Reply"
      bordered: true
      foreground: card.fg
      fontSize: Style.font.bodySmall
      property bool ccFocusable: visible
      function ccActivate() { clicked() }
      onClicked: card.replying = true
    }
    Loader {
      active: card.showReply && card.replying
      visible: active
      width: parent.width
      sourceComponent: Row {
        width: parent ? parent.width : 0
        spacing: Style.space(6)
        leftPadding: iconBox.width + Style.space(10)
        TextField {
          id: reply
          width: parent.width - parent.leftPadding - sendBtn.width - Style.space(6)
          placeholderText: card.row.replyPlaceholder || "Reply"
          foreground: card.fg
          property bool ccFocusable: visible
          property bool hasCursor: false
          function ccActivate() { forceActiveFocus() }
          Component.onCompleted: forceActiveFocus()
          Keys.onReturnPressed: sendBtn.clicked()
          Keys.onEscapePressed: function(event) { event.accepted = true; card.replying = false }
        }
        Button {
          id: sendBtn
          text: "Send"
          bordered: true
          foreground: card.fg
          fontSize: Style.font.bodySmall
          property bool ccFocusable: visible
          function ccActivate() { clicked() }
          onClicked: if (reply.text.trim() !== "") { card.svc.reply(card.row.id, reply.text); card.replying = false }
        }
      }
    }
  }
}
