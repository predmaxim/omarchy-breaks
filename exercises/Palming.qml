import QtQuick

Rectangle {
  property var step
  property var tr
  property color accent
  property color fg
  property real remaining
  signal finished()
  color: "black"
  Text {
    anchors.centerIn: parent; width: parent.width * 0.7; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
    text: tr("Close your eyes and cover them with warm palms. The sound will tell you when to open them")
    color: "#555"; font.pixelSize: 20
  }
}
