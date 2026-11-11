import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui

// Now Playing card: album cover, title/artist, a progress bar you can click to
// seek, previous / play-pause / next, and a switcher when several players
// are around. Shown only while a player is playing or paused.
Rectangle {
  id: np

  // playerctld only mirrors the other players; leave it out.
  readonly property var players: (Mpris.players ? Mpris.players.values : []).filter(function(p) {
    return p && String(p.dbusName || "").indexOf("playerctld") < 0 && p.playbackState !== MprisPlaybackState.Stopped
  })
  property string chosen: ""
  readonly property var player: {
    for (var i = 0; i < players.length; i++) if (players[i].dbusName === chosen) return players[i]
    for (var j = 0; j < players.length; j++) if (players[j].isPlaying) return players[j]
    return players.length ? players[0] : null
  }
  readonly property bool hasTrack: !!player && String(player.trackTitle || "") !== ""
  readonly property color fg: Color.menu.text

  visible: hasTrack
  width: parent ? parent.width : 0
  height: visible ? content.implicitHeight + Style.space(20) : 0
  radius: Math.max(10, Style.cornerRadius)
  color: Qt.rgba(fg.r, fg.g, fg.b, 0.06)
  border.width: 1
  border.color: Qt.rgba(fg.r, fg.g, fg.b, 0.10)

  // MPRIS doesn't push the position; ask for it while playing.
  Timer {
    interval: 1000; repeat: true
    running: np.visible && !!np.player && np.player.isPlaying
    onTriggered: if (np.player) np.player.positionChanged()
  }

  function clock(secs) {
    var s = Math.max(0, Math.floor(secs || 0))
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60
    return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (r < 10 ? "0" : "") + r
  }
  function playerName(p) { return p ? String(p.identity || p.dbusName || "Player").replace(/^org\.mpris\.MediaPlayer2\./, "") : "" }

  Row {
    id: content
    x: Style.space(10)
    y: Style.space(10)
    width: parent.width - Style.space(20)
    spacing: Style.space(12)

    ClippingRectangle {
      id: art
      width: Style.space(72)
      height: width
      radius: Style.space(8)
      color: Qt.rgba(np.fg.r, np.fg.g, np.fg.b, 0.10)
      Image {
        anchors.fill: parent
        source: np.player ? String(np.player.trackArtUrl || "") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 160
        sourceSize.height: 160
        visible: status === Image.Ready
      }
      Text {
        anchors.centerIn: parent
        visible: !np.player || !np.player.trackArtUrl
        text: String.fromCodePoint(0xF0387)
        color: Qt.rgba(np.fg.r, np.fg.g, np.fg.b, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.space(30)
      }
    }

    Column {
      width: parent.width - art.width - parent.spacing
      spacing: Style.space(4)

      Item {
        width: parent.width
        height: titleText.implicitHeight
        Text {
          id: titleText
          anchors.left: parent.left
          anchors.right: switcher.visible ? switcher.left : parent.right
          anchors.rightMargin: switcher.visible ? Style.space(6) : 0
          text: np.player ? String(np.player.trackTitle || "") : ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: np.fg
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }
        // Several players: click to switch between them.
        Rectangle {
          id: switcher
          visible: np.players.length > 1
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: swText.implicitWidth + Style.space(14)
          height: swText.implicitHeight + Style.space(4)
          radius: height / 2
          color: swMouse.containsMouse ? Qt.rgba(np.fg.r, np.fg.g, np.fg.b, 0.16) : Qt.rgba(np.fg.r, np.fg.g, np.fg.b, 0.08)
          Text {
            id: swText
            anchors.centerIn: parent
            text: np.playerName(np.player) + "  " + String.fromCodePoint(0xF04E1)
            color: np.fg
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            id: swMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var i = np.players.indexOf(np.player)
              np.chosen = np.players[(i + 1) % np.players.length].dbusName
            }
          }
        }
      }
      Text {
        width: parent.width
        text: np.player ? [np.player.trackArtist, np.player.trackAlbum].filter(function(x) { return x }).join(" · ") : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        visible: text !== ""
        color: Qt.rgba(np.fg.r, np.fg.g, np.fg.b, 0.65)
        font.family: Style.font.menuFamily
        font.pixelSize: Style.font.bodySmall
      }

      // Progress: click or drag to seek (when the player allows it).
      Item {
        width: parent.width
        height: Style.space(14)
        visible: !!np.player && np.player.lengthSupported && np.player.length > 0
        readonly property real frac: np.player && np.player.length > 0 ? Math.max(0, Math.min(1, np.player.position / np.player.length)) : 0
        Rectangle {
          id: track
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: Style.space(4)
          radius: height / 2
          color: Qt.rgba(np.fg.r, np.fg.g, np.fg.b, 0.15)
          Rectangle {
            width: parent.width * parent.parent.frac
            height: parent.height
            radius: parent.radius
            color: Color.accent
          }
        }
        MouseArea {
          anchors.fill: parent
          enabled: !!np.player && np.player.canSeek
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          function seekTo(x) { if (np.player) np.player.position = Math.max(0, Math.min(1, x / width)) * np.player.length }
          onPressed: function(m) { seekTo(m.x) }
          onPositionChanged: function(m) { if (pressed) seekTo(m.x) }
        }
      }

      Item {
        width: parent.width
        height: controls.height
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          visible: !!np.player && np.player.lengthSupported && np.player.length > 0
          text: np.player ? np.clock(np.player.position) + " / " + np.clock(np.player.length) : ""
          color: Qt.rgba(np.fg.r, np.fg.g, np.fg.b, 0.6)
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.bodySmall
        }
        Row {
          id: controls
          anchors.right: parent.right
          spacing: Style.space(6)
          QsRoundButton {
            width: Style.space(32)
            icon: String.fromCodePoint(0xF04AE)
            tip: "Previous"
            opacity: np.player && np.player.canGoPrevious ? 1 : 0.4
            onClicked: if (np.player && np.player.canGoPrevious) np.player.previous()
          }
          QsRoundButton {
            width: Style.space(32)
            active: true
            icon: np.player && np.player.isPlaying ? String.fromCodePoint(0xF03E4) : String.fromCodePoint(0xF040A)
            tip: np.player && np.player.isPlaying ? "Pause" : "Play"
            onClicked: if (np.player && np.player.canTogglePlaying) np.player.togglePlaying()
          }
          QsRoundButton {
            width: Style.space(32)
            icon: String.fromCodePoint(0xF04AD)
            tip: "Next"
            opacity: np.player && np.player.canGoNext ? 1 : 0.4
            onClicked: if (np.player && np.player.canGoNext) np.player.next()
          }
        }
      }
    }
  }
}
