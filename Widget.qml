import QtQuick
import Quickshell
import qs.Ui
import "logic.js" as L

// Minutes to the next break: eye or running man. Click: a break now; right
// click: pause 1 h (not in hard mode). The tooltip has today's numbers.
BarWidget {
  id: root
  moduleName: "predmaxim.breaks"

  property var service: null
  Timer {
    interval: 2000; repeat: true; running: root.service === null; triggeredOnStart: true
    onTriggered: {
      var host = root.bar && root.bar.shell ? root.bar.shell : null
      if (host && typeof host.serviceFor === "function") root.service = host.serviceFor("predmaxim.breaks")
    }
  }

  readonly property var d: service ? service.decision : ({ kind: "eyes", in: 0 })
  readonly property int minutes: Math.ceil(d.in / 60)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: (root.d.kind === "body" ? "\uf70c" : "\uf06e") + " " + root.minutes
    tooltipText: !root.service ? "" : [
      root.service.busyReason ? root.service.tr("Waiting: %1", root.service.tr(root.service.busyReason))
        : root.service.tr(root.d.kind === "body" ? "Next: body in %1 min" : "Next: eyes in %1 min", root.minutes),
      root.service.tr("Today: %1 breaks", L.todayStats(root.service.history, Date.now()).breaks),
      root.service.tr("Streak: %1 days", L.streak(root.service.history, Date.now())),
      root.service.tr("Click: break now. Right click: pause 1 h")
    ].join("\n")
    onPressed: function(button) {
      if (!root.service) return
      if (button === Qt.RightButton) root.service.pause(60)
      else if (root.service.breakSteps.length === 0) root.service.startBreak(root.d.kind)
    }
  }
}
