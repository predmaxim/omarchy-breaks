import QtQuick

Item {
  id: area
  property var step
  property var tr
  property color accent
  property color fg
  property real remaining
  signal finished()
  property int hits: 0
  property int jumps: 0

  onRemainingChanged: if (remaining <= 0) finished()

  Text { text: tr("Click the dot as soon as it jumps") + "   " + hits + " / " + jumps; color: fg; font.pixelSize: 18 }

  Rectangle {
    id: dot
    width: 36; height: 36; radius: 18; color: accent
    x: 0; y: 40
    MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: { area.hits++; jump.restart(); area.move() } }
  }
  function move() {
    // Corners and edges: wide jumps work the eye muscles, small ones do not.
    var xs = [0, 0.5, 1], ys = [0, 0.5, 1]
    dot.x = xs[Math.floor(Math.random() * 3)] * (area.width - dot.width)
    dot.y = 40 + ys[Math.floor(Math.random() * 3)] * (area.height - 40 - dot.height)
    area.jumps++
  }
  Timer { id: jump; interval: 1500; repeat: true; running: true; onTriggered: area.move() }
}
