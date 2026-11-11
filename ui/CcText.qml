import QtQuick
import qs.Commons

// Plain-text label: nothing bound here is ever interpreted as markup.
Text {
  textFormat: Text.PlainText
  color: Color.menu.text
  font.family: Style.font.menuFamily
  font.pixelSize: Style.font.body
  elide: Text.ElideRight
  renderType: Text.NativeRendering
}
