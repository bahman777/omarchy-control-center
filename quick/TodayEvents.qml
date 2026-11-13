import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// "Today" above the notifications: the next few events still to come today
// (or tomorrow's, once today is done), each with its calendar's colour.
// Join appears from 15 minutes before a meeting that has a Meet/Zoom link.
Column {
  id: today
  required property var svc          // NotifyService (calData)
  signal openCalendar(real dayMs)

  readonly property color fg: Color.menu.text
  property real now: Date.now()
  Timer { interval: 30000; running: today.visible; repeat: true; triggeredOnStart: true; onTriggered: today.now = Date.now() }

  readonly property var cals: {
    var m = {}
    ;((svc && svc.calData.calendars) || []).forEach(function(c) { m[c.id] = c })
    return m
  }
  readonly property real dayStart: { var d = new Date(now); d.setHours(0, 0, 0, 0); return d.getTime() }
  readonly property real dayEnd: dayStart + 86400000
  readonly property var todays: ((svc && svc.calData.events) || []).filter(function(e) {
    return e.end > today.now && e.start < today.dayEnd && (today.cals[e.cal] || {}).enabled !== false
  })
  readonly property var tomorrows: ((svc && svc.calData.events) || []).filter(function(e) {
    return e.start >= today.dayEnd && e.start < today.dayEnd + 86400000 && (today.cals[e.cal] || {}).enabled !== false
  })
  readonly property bool showTomorrow: todays.length === 0 && tomorrows.length > 0
  // Only the next event; the Calendar button has the rest.
  readonly property var upcoming: showTomorrow ? tomorrows : todays
  readonly property var shown: upcoming.slice(0, 1)

  visible: !!svc && ((svc.calData.calendars || []).length > 0)
  width: parent ? parent.width : 0
  spacing: Style.space(4)

  function hm(ms) { return Qt.formatTime(new Date(ms), "h:mm AP") }
  function when(e) {
    if (e.allDay) return "All day"
    if (e.start <= now && e.end > now) return "Now · until " + hm(e.end)
    var mins = Math.round((e.start - now) / 60000)
    if (!showTomorrow && mins < 60) return "In " + Math.max(1, mins) + " min · " + hm(e.start)
    return hm(e.start) + " – " + hm(e.end)
  }

  Item {
    width: parent.width
    height: Style.space(30)
    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      text: (today.showTomorrow ? "Tomorrow" : "Today  ·  " + Qt.formatDate(new Date(today.now), "ddd, MMM d"))
        + (today.upcoming.length > 1 ? "  ·  " + (today.upcoming.length - 1) + " more" : "")
      color: today.fg
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.subtitle
      font.weight: Font.DemiBold
    }
    Button {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "Calendar"
      bordered: true
      foreground: today.fg
      fontSize: Style.font.bodySmall
      property bool ccFocusable: visible
      function ccActivate() { clicked() }
      onClicked: today.openCalendar(today.dayStart)
    }
  }

  QsMenuItem {
    visible: today.shown.length === 0
    text: "Nothing else today or tomorrow"
    clickable: false
    dim: true
  }

  Repeater {
    model: today.shown
    delegate: Item {
      id: ev
      required property var modelData
      readonly property bool joinable: !!modelData.join && modelData.end > today.now && modelData.start - today.now < 900000
      width: today.width
      height: Style.space(46)
      Rectangle {
        anchors.fill: parent
        radius: Style.space(8)
        color: evMouse.containsMouse ? Qt.rgba(today.fg.r, today.fg.g, today.fg.b, 0.08) : "transparent"
      }
      Rectangle {
        id: dot
        x: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(4)
        height: parent.height - Style.space(14)
        radius: width / 2
        color: (today.cals[ev.modelData.cal] || {}).color || Color.accent
      }
      Column {
        anchors.left: dot.right
        anchors.leftMargin: Style.space(10)
        anchors.right: joinBtn.visible ? joinBtn.left : parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        Text {
          width: parent.width
          text: ev.modelData.title
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: today.fg
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }
        Text {
          width: parent.width
          text: today.when(ev.modelData) + (ev.modelData.location && !ev.modelData.join ? " · " + ev.modelData.location : "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: ev.modelData.start <= today.now && !ev.modelData.allDay ? Color.accent : Qt.rgba(today.fg.r, today.fg.g, today.fg.b, 0.62)
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
      MouseArea {
        id: evMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { var d = new Date(ev.modelData.start); d.setHours(0, 0, 0, 0); today.openCalendar(d.getTime()) }
      }
      Button {
        id: joinBtn
        visible: ev.joinable
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: "Join"
        bordered: true
        foreground: today.fg
        fontSize: Style.font.bodySmall
        property bool ccFocusable: visible
        function ccActivate() { clicked() }
        onClicked: Quickshell.execDetached(["xdg-open", ev.modelData.join])
      }
    }
  }
}
