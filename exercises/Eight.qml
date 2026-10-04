import QtQuick

Item {
  id: area
  property var step
  property var tr
  property color accent
  property color fg
  property real remaining
  signal finished()
  property real a: 0

  Text { text: tr("Only the eyes move, the head stays still"); color: fg; font.pixelSize: 18 }
  NumberAnimation on a { from: 0; to: Math.PI * 2; duration: 8000; loops: Animation.Infinite }
  Rectangle {
    width: 30; height: 30; radius: 15; color: accent
    x: area.width / 2 + Math.sin(area.a) * area.width * 0.42 - 15
    y: area.height / 2 + Math.sin(area.a * 2) * area.height * 0.38 - 15
  }
}
