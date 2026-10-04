import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "@PLUGIN_DIR@/I18n.js" as I18n

// predmaxim.breaks among the bar's indicators: a clock and the minutes to the
// next break, lit while breaks are on. Click toggles the modal of the hidden
// widget (Widget.qml). The service writes the state to
// $XDG_RUNTIME_DIR/predmaxim-breaks.json.
// keep-custom-widgets.sh copies this file into the predmaxim.indicators clone
// as indicators/Breaks.qml and fills in @PLUGIN_DIR@.
BarIndicator {
  id: root

  readonly property var tr: I18n.translator(I18n.textLanguage(function(name) { return Quickshell.env(name) }))
  property var info: ({ enabled: false, minutes: 0, kind: "eyes", busy: "" })
  readonly property string label: "󰥔 " + info.minutes

  active: info.enabled
  activeText: label
  inactiveText: "󰥔"
  activeTooltipText: info.busy ? root.tr("Waiting: %1", root.tr(info.busy))
    : root.tr(info.kind === "body" ? "Next: body in %1 min" : "Next: eyes in %1 min", info.minutes)
  inactiveTooltipText: root.tr("Breaks are off")

  onPressed: function(button) {
    Quickshell.execDetached(["omarchy-shell", "predmaxim.breaks-panel", "toggle"])
  }

  FileView {
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/predmaxim-breaks.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.info = JSON.parse(text()) } catch (e) {} }
  }
}
