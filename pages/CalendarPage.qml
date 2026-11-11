import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../ui"
import "../Icons.js" as Icons

// Month grid with a dot per calendar on days that have events, the chosen
// day's events, and the calendar links (Google "Secret address in iCal
// format", iCloud, Outlook, any .ics). Data comes from the background service
// (tools/calendar.py), which also sends the 10-minute meeting reminders.
CcPage {
  id: page

  readonly property var svc: cc.notifService
  readonly property var data: svc ? svc.calData : ({ calendars: [], events: [] })
  readonly property var cals: {
    var m = {}
    ;(data.calendars || []).forEach(function(c) { m[c.id] = c })
    return m
  }
  readonly property var events: (data.events || []).filter(function(e) { return (page.cals[e.cal] || {}).enabled !== false })

  function dayOf(ms) { var d = new Date(ms); d.setHours(0, 0, 0, 0); return d.getTime() }
  property real selectedDay: dayOf(cc.calendarDay > 0 ? cc.calendarDay : Date.now())
  property real monthStart: { var d = new Date(selectedDay); d.setDate(1); d.setHours(0, 0, 0, 0); return d.getTime() }
  Component.onCompleted: cc.calendarDay = 0

  function shiftMonth(n) {
    var d = new Date(monthStart); d.setMonth(d.getMonth() + n)
    monthStart = d.getTime()
    var s = new Date(selectedDay)
    if (s.getMonth() !== d.getMonth() || s.getFullYear() !== d.getFullYear()) selectedDay = d.getTime()
  }
  function goToday() { selectedDay = dayOf(Date.now()); var d = new Date(selectedDay); d.setDate(1); monthStart = d.getTime() }

  // Events overlapping [day, day + 1).
  function eventsOn(day) {
    var end = day + 86400000
    return events.filter(function(e) { return e.start < end && e.end > day && !(e.allDay && e.end === day) })
  }
  readonly property int firstDow: Qt.locale().firstDayOfWeek % 7      // 0 = Sunday
  readonly property var cells: {
    var first = new Date(monthStart)
    var lead = (first.getDay() - firstDow + 7) % 7
    var start = new Date(first); start.setDate(1 - lead)
    var out = []
    for (var i = 0; i < 42; i++) {
      var d = new Date(start); d.setDate(start.getDate() + i); d.setHours(0, 0, 0, 0)
      out.push({ ms: d.getTime(), n: d.getDate(), inMonth: d.getMonth() === first.getMonth() })
    }
    return out
  }
  readonly property var dayEvents: eventsOn(selectedDay)

  function hm(ms) { return Qt.formatTime(new Date(ms), "h:mm AP") }
  function run(args, msg) {
    if (!svc) return
    svc.calRun(args, function(o) { if (msg) page.cc.toast(o && o.error ? o.error : msg) })
  }
  readonly property var palette: ["#4f8cf7", "#3fb98f", "#e0688a", "#e8a33d", "#c07ee8", "#47b5c4"]
  function nextColor(c) { var i = palette.indexOf(String(c).toLowerCase()); return palette[(i + 1) % palette.length] }

  // ------------------------------------------------------------ month
  CcGroup {
    title: Qt.formatDate(new Date(page.monthStart), "MMMM yyyy")
    subtitle: page.svc && page.svc.calBusy ? "Updating…"
      : page.data.updated ? "Updated " + Qt.formatTime(new Date(page.data.updated), "h:mm AP") : ""
    header: [
      CcButton { text: "‹"; tooltipText: "Previous month"; onClicked: page.shiftMonth(-1) },
      CcButton { text: "Today"; onClicked: page.goToday() },
      CcButton { text: "›"; tooltipText: "Next month"; onClicked: page.shiftMonth(1) }
    ]
    Column {
      width: parent ? parent.width : 0
      topPadding: Style.space(8)
      bottomPadding: Style.space(8)
      Row {
        x: Style.space(8)
        Repeater {
          model: 7
          delegate: Text {
            required property int index
            width: (page.width > 0 ? (parent.parent.width - Style.space(16)) / 7 : 40)
            horizontalAlignment: Text.AlignHCenter
            text: Qt.locale().dayName((index + page.firstDow) % 7, Locale.ShortFormat)
            color: Qt.rgba(page.cc.fg.r, page.cc.fg.g, page.cc.fg.b, 0.55)
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
      Grid {
        id: grid
        x: Style.space(8)
        columns: 7
        readonly property real cellW: (parent.width - Style.space(16)) / 7
        Repeater {
          model: page.cells
          delegate: Item {
            id: cell
            required property var modelData
            readonly property bool isToday: modelData.ms === page.dayOf(Date.now())
            readonly property bool isSel: modelData.ms === page.selectedDay
            readonly property var evs: page.eventsOn(modelData.ms)
            width: grid.cellW
            height: Style.space(44)
            Rectangle {
              anchors.centerIn: parent
              width: Math.min(parent.width, parent.height) - Style.space(4)
              height: width
              radius: width / 2
              color: cell.isSel ? Qt.rgba(page.cc.accent.r, page.cc.accent.g, page.cc.accent.b, 0.25)
                : cellMouse.containsMouse ? Qt.rgba(page.cc.fg.r, page.cc.fg.g, page.cc.fg.b, 0.08) : "transparent"
              border.width: cell.isToday ? 2 : 0
              border.color: page.cc.accent
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              y: Style.space(9)
              text: String(cell.modelData.n)
              color: cell.isToday ? page.cc.accent : page.cc.fg
              opacity: cell.modelData.inMonth ? 1 : 0.35
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              font.bold: cell.isToday || cell.isSel
            }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              y: parent.height - Style.space(12)
              spacing: Style.space(3)
              Repeater {
                model: {
                  var seen = [], out = []
                  cell.evs.forEach(function(e) { if (seen.indexOf(e.cal) < 0 && out.length < 3) { seen.push(e.cal); out.push((page.cals[e.cal] || {}).color || "#888888") } })
                  return out
                }
                delegate: Rectangle {
                  required property var modelData
                  width: Style.space(5); height: width; radius: width / 2
                  color: modelData
                  opacity: cell.modelData.inMonth ? 1 : 0.4
                }
              }
            }
            MouseArea {
              id: cellMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                page.selectedDay = cell.modelData.ms
                if (!cell.modelData.inMonth) { var d = new Date(cell.modelData.ms); d.setDate(1); page.monthStart = d.getTime() }
              }
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ day
  CcGroup {
    title: Qt.formatDate(new Date(page.selectedDay), "dddd, MMMM d")
    subtitle: page.dayEvents.length === 0 ? "No events" : page.dayEvents.length + (page.dayEvents.length === 1 ? " event" : " events")
    header: [ CcButton {
      text: "Google Calendar"
      tooltipText: "Open this day in Google Calendar"
      onClicked: { var d = new Date(page.selectedDay); page.cc.launch(["xdg-open", "https://calendar.google.com/calendar/r/day/" + d.getFullYear() + "/" + (d.getMonth() + 1) + "/" + d.getDate()], 0) }
    } ]
    Repeater {
      model: page.dayEvents
      delegate: CcRow {
        required property var modelData
        icon: "●"
        iconColor: (page.cals[modelData.cal] || {}).color || page.cc.accent
        title: modelData.title
        subtitle: (modelData.allDay ? "All day" : page.hm(modelData.start) + " – " + page.hm(modelData.end))
          + (modelData.location ? " · " + modelData.location : "") + " · " + ((page.cals[modelData.cal] || {}).name || "")
        CcButton {
          visible: !!modelData.join
          text: "Join"
          tooltipText: modelData.join
          onClicked: page.cc.launch(["xdg-open", modelData.join], 0)
        }
      }
    }
  }

  // ------------------------------------------------------------ calendars
  CcGroup {
    title: "Calendars"
    subtitle: "A reminder pops up 10 minutes before each meeting. Click the dot to change a colour."
    header: [ CcButton { text: page.svc && page.svc.calBusy ? "Updating…" : "Refresh"; onClicked: page.run(["events", "--refresh"], "Calendars updated") } ]
    Repeater {
      model: page.data.calendars || []
      delegate: CcRow {
        id: calRow
        required property var modelData
        icon: "●"
        iconColor: modelData.color
        dim: !modelData.enabled
        title: modelData.name
        subtitle: modelData.error ? "Couldn't update: " + modelData.error + " (showing saved copy)" : modelData.host
        subtitleColor: modelData.error ? page.cc.urgent : Qt.rgba(page.cc.fg.r, page.cc.fg.g, page.cc.fg.b, 0.62)
        clickable: true
        tip: "Change colour"
        onClicked: page.run(["set", modelData.id, "color=" + page.nextColor(modelData.color)], "")
        TextField {
          width: Style.space(130)
          placeholderText: "Rename"
          foreground: page.cc.fg
          property bool ccFocusable: visible
          property bool hasCursor: false
          function ccActivate() { forceActiveFocus() }
          Keys.onReturnPressed: { if (text.trim()) page.run(["set", calRow.modelData.id, "name=" + text.trim()], "Renamed"); text = "" }
        }
        CcButton {
          text: calRow.modelData.enabled ? "Hide" : "Show"
          tooltipText: calRow.modelData.enabled ? "Hide its events and reminders" : "Show its events again"
          onClicked: page.run(["set", calRow.modelData.id, "enabled=" + (calRow.modelData.enabled ? "false" : "true")], "")
        }
        CcButton {
          text: "Remove"
          onClicked: page.run(["remove", calRow.modelData.id], "Calendar removed")
        }
      }
    }
    CcRow {
      title: "Add a calendar"
      subtitle: "Google: Calendar settings → your calendar → Integrate calendar → \"Secret address in iCal format\""
      TextField {
        id: newLink
        width: Style.space(230)
        placeholderText: "https://…/basic.ics"
        foreground: page.cc.fg
        property bool ccFocusable: visible
        property bool hasCursor: false
        function ccActivate() { forceActiveFocus() }
        Keys.onReturnPressed: addBtn.clicked()
      }
      CcButton {
        id: addBtn
        text: "Add"
        onClicked: { var t = newLink.text.trim(); if (t) { page.run(["add", t], "Calendar added"); newLink.text = "" } }
      }
    }
  }
}
