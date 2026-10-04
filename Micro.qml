import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// The micro-pause: no lock, a card at the top centre, where notifications
// pop up. It is done by itself after microSeconds without input (the
// IdleMonitor in Service.qml). Notifications share the Overlay layer and a
// newer surface goes on top, so the card maps itself again over each one.
Item {
  id: root
  property var service: null
  readonly property var s: service
  property bool raised: true

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.s || !root.s.microShown || event.name !== "openlayer" || event.data.indexOf("omarchy-notifications") < 0) return
      root.raised = false
      Qt.callLater(function() { root.raised = true })
    }
  }

  Variants {
    model: s && s.microShown && root.raised ? Quickshell.screens : []
    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: !Hyprland.focusedMonitor || modelData.name === Hyprland.focusedMonitor.name
        anchors.top: true
        // Below the bar like a toast, over the windows without pushing them.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        margins.top: Style.gapsOut
        implicitWidth: card.implicitWidth + 64
        implicitHeight: 96
        color: "transparent"
        WlrLayershell.namespace: "predmaxim-breaks-micro"
        WlrLayershell.layer: WlrLayer.Overlay
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
