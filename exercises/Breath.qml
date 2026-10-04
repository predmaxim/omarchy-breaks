import QtQuick

Item {
  property var step
  property var tr
  property color accent
  property color fg
  property real remaining
  signal finished()

  readonly property var pattern: step && step.pattern ? step.pattern : [4, 4, 4, 4]
  readonly property int cycle: pattern[0] + pattern[1] + pattern[2] + pattern[3]
  readonly property real t: step ? (step.seconds - remaining) % cycle : 0
  readonly property int phase: t < pattern[0] ? 0 : t < pattern[0] + pattern[1] ? 1 : t < pattern[0] + pattern[1] + pattern[2] ? 2 : 3
  readonly property real size: phase === 0 ? 0.4 + 0.6 * t / pattern[0] : phase === 1 ? 1 : phase === 2 ? 1 - 0.6 * (t - pattern[0] - pattern[1]) / pattern[2] : 0.4

  Rectangle {
    anchors.centerIn: parent
    width: 320 * size; height: width; radius: width / 2
    color: Qt.rgba(accent.r, accent.g, accent.b, 0.25); border.color: accent; border.width: 4
    Behavior on width { NumberAnimation { duration: 1000 } }
  }
  Text {
    anchors.centerIn: parent
    text: tr(["Inhale", "Hold", "Exhale", "Hold"][phase])
    color: fg; font.pixelSize: 32
  }
}
