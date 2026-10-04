import QtQuick

Item {
  property var step
  property var tr
  property color accent
  property color fg
  property real remaining
  signal finished()

  readonly property int done: step && step.reps ? Math.min(step.reps, Math.floor((step.seconds - remaining) / (step.seconds / step.reps))) : 0

  Column {
    anchors.centerIn: parent
    spacing: 24
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 160; height: 160; radius: 80
      color: "transparent"; border.color: accent; border.width: 6
      SequentialAnimation on scale {
        loops: Animation.Infinite
        running: step && step.reps > 0
        NumberAnimation { to: 0.6; duration: step && step.reps ? step.seconds / step.reps * 500 : 1000 }
        NumberAnimation { to: 1.0; duration: step && step.reps ? step.seconds / step.reps * 500 : 1000 }
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: step && step.reps ? done + " / " + step.reps : ""
      color: fg; font.pixelSize: 48; font.bold: true
    }
  }
}
