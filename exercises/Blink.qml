import QtQuick

Item {
  property var step
  property var tr
  property color accent
  property color fg
  property real remaining
  signal finished()
  readonly property bool closed: step ? (step.seconds - remaining) % 3 < 2 : false
  Text { anchors.centerIn: parent; text: tr(closed ? "Close" : "Open"); color: closed ? fg : accent; font.pixelSize: 56 }
}
