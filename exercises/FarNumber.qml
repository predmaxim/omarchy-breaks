import QtQuick

Item {
  id: area
  property var step
  property var tr
  property color accent
  property color fg
  property real remaining
  signal finished()
  readonly property int digit: Math.floor(Math.random() * 9) + 1
  property bool asking: false
  property string verdict: ""

  onRemainingChanged: if (remaining <= 0 && !asking) { asking = true; answer.forceActiveFocus() }

  Text { text: tr("Look at something 6 m away. Which number flashed in the corner?"); color: fg; font.pixelSize: 18; width: parent.width; wrapMode: Text.WordWrap }
  Text {
    id: flash
    text: area.digit; color: fg; opacity: 0; font.pixelSize: 28
    anchors.right: parent.right; anchors.bottom: parent.bottom
  }
  // The digit shows once, somewhere in the first two thirds of the step.
  Timer {
    interval: 3000 + Math.random() * 15000; running: true
    onTriggered: { flash.opacity = 1; hide.start() }
  }
  Timer { id: hide; interval: 600; onTriggered: flash.opacity = 0 }

  TextInput {
    id: answer
    visible: area.asking && area.verdict === ""
    anchors.centerIn: parent
    color: fg; font.pixelSize: 64; maximumLength: 1
    validator: IntValidator { bottom: 1; top: 9 }
    onAccepted: area.verdict = Number(text) === area.digit ? tr("Correct") : tr("It was %1", area.digit)
  }
  Text { visible: area.verdict !== ""; anchors.centerIn: parent; text: area.verdict; color: accent; font.pixelSize: 40 }
  Timer { interval: 1500; running: area.verdict !== ""; onTriggered: area.finished() }
}
