import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "logic.js" as L
import "I18n.js" as I18n

// The bar shows the icon through predmaxim.indicators (Indicator.qml); this
// widget stays in the layout, hidden, for its settings and IPC
// (`omarchy-shell predmaxim.breaks-panel toggle`). Its modal, in the middle of
// the screen like todo's, is a list of rows (logic.js rowsFor) on two pages:
// main (on/off and settings buttons in the header, everyday switches) and
// settings. ↑/↓ walk the rows, ←/→ change the value or the header button,
// Enter toggles or presses, Esc goes back from settings, then closes.
// Rare settings (break lengths, idle threshold…) stay in shell.json. Settings
// are written by the service into this entry.
Panel {
  id: root
  moduleName: "predmaxim.breaks"
  ipcTarget: "predmaxim.breaks-panel"

  readonly property var tr: I18n.translator(I18n.textLanguage(Quickshell.env))
  property var service: null
  property string page: "main"
  property int cursor: 0
  // Header button under the cursor: main 0 on/off, 1 settings; settings 0 Back.
  property int headCol: 0

  // The service is a separate plugin instance; look it up until it is there.
  Timer {
    interval: 2000; repeat: true; running: root.service === null; triggeredOnStart: true
    onTriggered: {
      var host = root.bar && root.bar.shell ? root.bar.shell : null
      if (host && typeof host.serviceFor === "function") root.service = host.serviceFor("predmaxim.breaks")
    }
  }

  readonly property var s: service ? service.settings : L.normalize({})
  readonly property var d: service ? service.decision : ({ kind: "eyes", in: 0 })
  readonly property int minutes: Math.ceil(d.in / 60)
  readonly property var rows: L.rowsFor(page, s)
  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string font: Style.font.family

  readonly property string nextText: !service ? ""
    : !s.enabled ? tr("Breaks are off")
    : service.busyReason ? tr("Waiting: %1", tr(service.busyReason))
    : tr(d.kind === "body" ? "Next: body in %1 min" : "Next: eyes in %1 min", minutes)
  readonly property var today: service ? L.todayStats(service.history, Date.now()) : ({ breaks: 0, reps: {} })
  readonly property int streak: service ? L.streak(service.history, Date.now()) : 0

  onOpenedChanged: if (opened) { root.page = "main"; root.cursor = 1; Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  onRowsChanged: if (root.cursor >= root.rows.length) root.cursor = root.rows.length - 1

  function set(key, value) {
    var change = {}
    change[key] = value
    if (root.service) root.service.store(change)
  }

  function move(dy) {
    root.cursor = Math.max(0, Math.min(root.rows.length - 1, root.cursor + dy))
    pointerGate.reset()
  }

  function showPage(p) {
    root.page = p
    root.cursor = 1
    root.headCol = 0
  }
  function back() {
    if (root.page === "settings") root.showPage("main")
    else root.close()
  }

  // ←/→: the button in the header, the value elsewhere.
  function change(i, dx) {
    var row = root.rows[i]
    if (!row) return
    if (row.type === "head") {
      root.headCol = Math.max(0, Math.min(root.page === "main" ? 1 : 0, root.headCol + dx))
      return
    }
    var c = L.adjust(row, root.s, dx)
    if (c) root.set(c.key, c.value)
  }

  // Enter or a click: toggle, press, or step a choice forward.
  function activate(i) {
    var row = root.rows[i]
    if (!row || !root.service) return
    if (row.key === "breakNow") { root.close(); root.service.startBreak(root.d.kind) }
    else if (row.key === "pause") { root.service.pause(60); root.close() }
    else if (row.type === "head") {
      if (root.page === "settings") root.showPage("main")
      else if (root.headCol === 0) root.set("enabled", !root.s.enabled)
      else root.showPage("settings")
    }
    else if (row.type === "switch" || row.type === "choice") root.change(i, 1)
  }

  visible: false
  implicitWidth: 0
  implicitHeight: 0

  // A click on the dimmed screen or Esc closes it.
  PanelWindow {
    id: modal
    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
    visible: root.opened
    color: Color.menu.scrim
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "predmaxim-breaks-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(440), modal.width - Style.space(80))
      height: Math.min(column.implicitHeight + card.contentTopInset + card.contentBottomInset, modal.height * 0.85)
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent }   // clicks on the card stay on it

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        focus: true
        onMoveRequested: function(dx, dy) {
          if (dy) root.move(dy)
          else if (dx) root.change(root.cursor, dx)
        }
        onActivateRequested: root.activate(root.cursor)
        onCloseRequested: root.back()

        PointerMoveGate { id: pointerGate; referenceItem: column }

        Column {
          id: column
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.spacing.xs

          PanelHero {
            width: column.width
            title: root.tr(root.page === "settings" ? "Settings" : "Breaks")
            meta: root.nextText
            foreground: root.fg
            fontFamily: root.font
            iconComponent: Text {
              text: "󰥔"
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.display
            }
            // On/off and settings, or Back on the settings page; ←/→ on the
            // header row picks one.
            trailingControl: Row {
              spacing: Style.space(6)
              Repeater {
                model: root.page === "main" ? [
                  { icon: "󰐥", label: root.s.enabled ? "On" : "Off", tip: root.s.enabled ? "Turn off" : "Turn on" },
                  { icon: "󰒓", tip: "Settings" }
                ] : [{ icon: "󰁍", tip: "Back" }]
                Button {
                  required property var modelData
                  required property int index
                  iconText: modelData.icon
                  text: modelData.label ? root.tr(modelData.label) : ""
                  fontSize: Style.font.bodySmall
                  iconSize: Style.font.title
                  tooltipText: root.tr(modelData.tip)
                  foreground: root.fg
                  fontFamily: root.font
                  bordered: true
                  active: root.page === "main" && index === 0 && root.s.enabled
                  hasCursor: root.cursor === 0 && root.headCol === index
                  onClicked: { root.cursor = 0; root.headCol = index; root.activate(0) }
                }
              }
            }
          }

          Text {
            text: [root.tr("Today: %1 breaks", root.today.breaks), root.tr("Streak: %1 days", root.streak)].join(" · ").toUpperCase()
            color: root.dim
            font.family: root.font
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            bottomPadding: Style.space(8)
          }

          Repeater {
            model: root.rows

            CursorSurface {
              id: row
              required property var modelData
              required property int index
              visible: modelData.type !== "head"
              width: column.width
              implicitHeight: Math.max(Style.space(42), control.implicitHeight + Style.spacing.xs * 2)
              foreground: root.fg
              hasCursor: root.cursor === index

              MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: function(mouse) { if (pointerGate.moved(area, mouse)) root.cursor = row.index }
                onClicked: { root.cursor = row.index; root.activate(row.index) }
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.right: control.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.label ? root.tr(row.modelData.label) : ""
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.body
                font.bold: row.modelData.type === "action"
                elide: Text.ElideRight
              }

              // The value on the right; ←/→ change it, so it is only a picture
              // for the keyboard, while the mouse can still use it directly.
              Loader {
                id: control
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: ({ num: numControl, switch: switchControl, choice: choiceControl })[row.modelData.type] || null

                Component {
                  id: choiceControl
                  ButtonGroup {
                    options: [{ value: "hard", label: root.tr("Hard") }, { value: "medium", label: root.tr("Medium") }, { value: "soft", label: root.tr("Soft") }]
                    value: root.s.strictness
                    focusable: false
                    foreground: root.fg
                    fontFamily: root.font
                    onChanged: function(v) { root.set("strictness", v) }
                  }
                }
                Component {
                  id: numControl
                  Row {
                    spacing: Style.space(10)
                    Repeater {
                      model: [-1, 0, 1]
                      Text {
                        required property int modelData
                        text: modelData < 0 ? "‹" : modelData > 0 ? "›" : root.s[row.modelData.key]
                        color: modelData === 0 ? root.fg : root.dim
                        font.family: root.font
                        font.pixelSize: Style.font.body
                        font.bold: true
                        MouseArea {
                          anchors.fill: parent
                          anchors.margins: -Style.space(6)
                          enabled: parent.modelData !== 0
                          onClicked: { root.cursor = row.index; root.change(row.index, parent.modelData) }
                        }
                      }
                    }
                  }
                }
                Component {
                  id: switchControl
                  ToggleSwitch {
                    checked: root.s[row.modelData.key]
                    foreground: root.fg
                    onToggled: root.change(row.index, 1)
                  }
                }
              }
            }
          }

          Text {
            width: column.width
            topPadding: Style.space(8)
            text: root.tr("↑↓ choose · ←→ change · Enter toggle · Esc close")
            color: root.dim
            font.family: root.font
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
