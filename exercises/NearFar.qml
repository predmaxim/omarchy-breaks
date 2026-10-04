import QtQuick

Item {
  property var step
  property var tr
  property color accent
  property color fg
  property real remaining
  signal finished()
  readonly property bool near: step ? Math.floor((step.seconds - remaining) / 5) % 2 === 0 : true
  Text {
    anchors.centerIn: parent
    text: tr(near ? "Near: your finger" : "Far: out of the window")
    color: near ? fg : accent; font.pixelSize: 48
  }
}
