import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// The micro-pause: no lock, a card in the middle of the screen. It is done by itself after
// microSeconds without input (the IdleMonitor in Service.qml).
Item {
  property var service: null
  readonly property var s: service

  Variants {
    model: s && s.microShown ? Quickshell.screens : []
    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: !Hyprland.focusedMonitor || modelData.name === Hyprland.focusedMonitor.name
        // No anchors: the layer sits in the middle of the screen.
        implicitWidth: card.implicitWidth + 64
        implicitHeight: 96
        color: "transparent"
        WlrLayershell.namespace: "predmaxim-breaks-micro"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
          anchors.fill: parent; radius: 8
          color: Color.background; border.color: Color.accent
          Text {
            id: card
            anchors.centerIn: parent
            text: "  " + s.tr("Look out of the window for %1 s", s.settings.microSeconds)
            color: Color.foreground; font.pixelSize: 22
          }
          MouseArea { anchors.fill: parent; onClicked: s.finishMicro(false) }
        }
      }
    }
  }
}
