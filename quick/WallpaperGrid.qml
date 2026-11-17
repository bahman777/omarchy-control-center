import QtQuick
import Quickshell
import qs.Commons

// The current theme's backgrounds plus your own (the same two folders
// `omarchy theme bg next` cycles through), as thumbnails. Clicking one sets
// it with Omarchy's command; the one in use is outlined. Videos show as a
// tile with a play mark.
Column {
  id: grid
  required property var runner
  property int columns: 3
  property var items: []          // [{ path, name, video }]
  property string current: ""
  readonly property color fg: Color.menu.text
  spacing: Style.space(8)
  width: parent ? parent.width : 300

  function refresh() {
    runner.run(["sh", "-c",
      "t=$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null); " +
      "readlink -f \"$HOME/.local/state/omarchy/current/background\" 2>/dev/null; echo @@; " +
      "find -L \"$HOME/.config/omarchy/backgrounds/$t/\" \"$HOME/.local/state/omarchy/current/theme/backgrounds/\" -maxdepth 1 -type f " +
      "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mov' \\) 2>/dev/null | sort"],
      function(code, out) {
        var s = String(out), i = s.indexOf("@@")
        grid.current = s.slice(0, i).trim()
        var seen = {}
        grid.items = s.slice(i + 2).split("\n").map(function(l) { return l.trim() }).filter(function(p) {
          if (!p || seen[p]) return false
          seen[p] = true
          return true
        }).map(function(p) {
          return { path: p, name: p.replace(/^.*\//, "").replace(/\.[^.]+$/, ""), video: /\.(mp4|webm|mov)$/i.test(p) }
        })
      })
  }
  Component.onCompleted: refresh()

  function set(path) {
    current = path
    runner.run(["omarchy-theme-bg-set", path], function() { grid.refresh() })
  }

  Grid {
    id: tiles
    width: parent.width
    columns: grid.columns
    spacing: Style.space(8)
    readonly property real cellW: (width - spacing * (columns - 1)) / columns
    Repeater {
      model: grid.items
      delegate: Rectangle {
        id: tile
        required property var modelData
        readonly property bool isCurrent: grid.current === modelData.path
        width: tiles.cellW
        height: Math.round(width * 0.62)
        radius: Style.space(8)
        color: Qt.rgba(grid.fg.r, grid.fg.g, grid.fg.b, 0.08)
        border.width: isCurrent ? 3 : (mouse.containsMouse ? 1 : 0)
        border.color: isCurrent ? Color.accent : Qt.rgba(grid.fg.r, grid.fg.g, grid.fg.b, 0.4)
        clip: true
        Image {
          anchors.fill: parent
          anchors.margins: tile.isCurrent ? 3 : 0
          visible: !tile.modelData.video
          // Each path segment escaped: a name like "th?id=…jpg" (Bing) would
          // otherwise be cut at the "?" and load nothing.
          source: tile.modelData.video ? "" : "file://" + tile.modelData.path.split("/").map(encodeURIComponent).join("/")
          sourceSize.width: 320
          sourceSize.height: 200
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
        }
        Text {
          anchors.centerIn: parent
          visible: tile.modelData.video
          text: String.fromCodePoint(0xF040A)
          color: grid.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.iconLarge
        }
        Rectangle {
          visible: tile.isCurrent
          anchors { right: parent.right; bottom: parent.bottom; margins: Style.space(6) }
          width: Style.space(18); height: width; radius: width / 2
          color: Color.accent
          Text {
            anchors.centerIn: parent
            text: ""
            color: Qt.rgba(Color.menu.background.r, Color.menu.background.g, Color.menu.background.b, 1)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: grid.set(tile.modelData.path)
        }
        // Keyboard cursor contract (see QuickContent.moveCursor).
        property bool ccFocusable: visible
        property bool hasCursor: false
        function ccActivate() { grid.set(modelData.path) }
        Rectangle {
          anchors.fill: parent
          radius: parent.radius
          color: "transparent"
          border.width: tile.hasCursor ? 2 : 0
          border.color: Color.accent
        }
      }
    }
  }

  Text {
    visible: grid.items.length === 0
    text: "This theme has no backgrounds yet"
    color: Qt.rgba(grid.fg.r, grid.fg.g, grid.fg.b, 0.6)
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.bodySmall
  }
}
