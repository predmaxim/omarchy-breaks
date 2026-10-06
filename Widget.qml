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
  // Header button under the cursor: main 0 settings, 1 on/off; settings 0 Back.
  property int headCol: 0
  // Day under the cursor on the work days row: 0 Mon … 6 Sun.
  property int dayCol: 0
  // The working hours being edited, as in the Workspaces schedule: saved only
  // when L.scheduleError has nothing against them, the error under the row.
  property var draft: ({ workDays: "", workFrom: "", workTo: "" })
  property string scheduleError: ""
  // A time field has the keys: the catcher lets them through.
  readonly property bool typing: keyCatcher.Window.activeFocusItem !== null && keyCatcher.Window.activeFocusItem !== keyCatcher
  signal pressRow(int i)

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
    : service.offHours ? tr("Outside working hours")
    : service.busyReason ? tr("Waiting: %1", tr(service.busyReason))
    : tr(d.kind === "body" ? "Next: body in %1 min" : "Next: eyes in %1 min", minutes)
  readonly property var today: service ? L.todayStats(service.history, Date.now()) : ({ breaks: 0, reps: {} })
  readonly property int streak: service ? L.streak(service.history, Date.now()) : 0

  onOpenedChanged: if (opened) { root.loadDraft(); root.page = "main"; root.cursor = 1; Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  onRowsChanged: if (root.cursor >= root.rows.length) root.cursor = root.rows.length - 1

  function set(key, value) {
    var change = {}
    change[key] = value
    if (root.service) root.service.store(change)
  }

  function loadDraft() {
    root.draft = { workDays: root.s.workDays, workFrom: root.s.workFrom, workTo: root.s.workTo }
    root.scheduleError = ""
  }
  function setDraft(change) {
    var d = Object.assign({}, root.draft, change), err = L.scheduleError(d.workDays, d.workFrom, d.workTo)
    root.draft = d
    root.scheduleError = err === "days" ? root.tr("Pick the days") : err === "time" ? root.tr("Time is HH:MM")
      : err === "order" ? root.tr("The end must be after the start") : ""
    if (!err && root.service) root.service.store(d)
  }

  function move(dy) {
    root.cursor = Math.max(0, Math.min(root.rows.length - 1, root.cursor + dy))
    pointerGate.reset()
  }

  function showPage(p) {
    root.page = p
    root.cursor = 1
    root.headCol = p === "main" ? 1 : 0
  }
  function back() {
    if (root.page === "settings") root.showPage("main")
    else root.close()
  }

  // ←/→: the button in the header, the day on the work days row, the value elsewhere.
  function change(i, dx) {
    var row = root.rows[i]
    if (!row) return
    if (row.type === "head") {
      root.headCol = Math.max(0, Math.min(root.page === "main" ? 2 : 0, root.headCol + dx))
      return
    }
    if (row.type === "days") {
      root.dayCol = Math.max(0, Math.min(6, root.dayCol + dx))
      return
    }
    var c = L.adjust(row, root.s, dx)
    if (c) root.set(c.key, c.value)
  }

  // Enter or a click: toggle, press, step a choice forward, switch the day, or type the time.
  function activate(i) {
    var row = root.rows[i]
    if (!row || !root.service) return
    if (row.key === "pause") { root.service.pause(60); root.close() }
    else if (row.type === "head") {
      // Main page: Break now, Settings, the switch; settings page: only Back.
      if (root.page === "settings") root.showPage("main")
      else if (root.headCol === 0) { root.close(); root.service.startBreak(root.d.kind) }
      else if (root.headCol === 2) root.set("enabled", !root.s.enabled)
      else root.showPage("settings")
    }
    else if (row.type === "days") root.setDraft({ workDays: L.toggleDay(root.draft.workDays, root.dayCol + 1) })
    else if (row.type === "time") root.pressRow(i)
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
        blocked: root.typing
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
            // The stock header pattern (Wi-Fi, audio): Break now, the settings button, then
            // the on/off ToggleSwitch at the right edge; on the settings page
            // only Back, at the edge; ←/→ on the header row picks one.
            trailingControl: Row {
              spacing: Style.space(10)
              // Today's breaks; the streak is in the tooltip.
              Text {
                visible: root.page === "main"
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.breaks
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.displayLarge
                font.bold: true
                HoverHandler { id: statsHover }
                PanelToolTip { visible: statsHover.hovered; text: [root.tr("Today: %1 breaks", root.today.breaks), root.tr("Streak: %1 days", root.streak)].join(" · ") }
              }
              Button {
                visible: root.page === "main"
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰾩"
                iconSize: Style.font.subtitle * 1.5
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(2)
                width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
                height: width
                tooltipText: root.tr("Break now")
                foreground: root.fg
                fontFamily: root.font
                hasCursor: root.cursor === 0 && root.headCol === 0
                onClicked: { root.cursor = 0; root.headCol = 0; root.activate(0) }
              }
              Button {
                readonly property bool back: root.page === "settings"
                anchors.verticalCenter: parent.verticalCenter
                iconText: back ? "󰁍" : "󰒓"
                iconSize: Style.font.subtitle * 1.5
                horizontalPadding: Style.space(5)
                verticalPadding: Style.space(2)
                width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
                height: width
                tooltipText: root.tr(back ? "Back" : "Settings")
                foreground: root.fg
                fontFamily: root.font
                hasCursor: root.cursor === 0 && root.headCol === (back ? 0 : 1)
                onClicked: { root.cursor = 0; root.headCol = back ? 0 : 1; root.activate(0) }
              }
              ToggleSwitch {
                visible: root.page === "main"
                anchors.verticalCenter: parent.verticalCenter
                checked: root.s.enabled
                hasCursor: root.cursor === 0 && root.headCol === 2
                foreground: root.fg
                onToggled: { root.cursor = 0; root.headCol = 2; root.activate(0) }
                PanelToolTip { visible: parent.containsMouse; text: root.tr(root.s.enabled ? "Turn off" : "Turn on") }
              }
            }
          }

          // The Bluetooth panel's gap: Style.space(14) above and below the line.
          Item {
            width: column.width
            height: Style.space(14) * 2 + 1 - column.spacing * 2
            PanelSeparator { anchors.verticalCenter: parent.verticalCenter; foreground: root.fg }
          }

          Repeater {
            model: root.rows

            CursorSurface {
              id: row
              required property var modelData
              required property int index
              visible: modelData.type !== "head"
              width: column.width
              implicitHeight: Math.max(Style.space(42), control.implicitHeight + Style.spacing.xs * 2, labels.implicitHeight + Style.spacing.xs * 2)
              foreground: root.fg
              hasCursor: root.cursor === index

              MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: function(mouse) { if (pointerGate.moved(area, mouse)) root.cursor = row.index }
                onClicked: { root.cursor = row.index; root.activate(row.index) }
              }

              // The label; under "Work until", why the working hours aren't saved.
              Column {
                id: labels
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.rowPaddingX
                anchors.right: control.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  width: parent.width
                  text: row.modelData.label ? root.tr(row.modelData.label) : ""
                  color: root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.body
                  font.bold: row.modelData.type === "action"
                  elide: Text.ElideRight
                }
                Text {
                  visible: text !== ""
                  width: parent.width
                  text: row.modelData.key === "workTo" ? root.scheduleError : ""
                  color: Color.urgent
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              // The value on the right; ←/→ change it, so it is only a picture
              // for the keyboard, while the mouse can still use it directly.
              Loader {
                id: control
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.rowPaddingX
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: ({ num: numControl, time: timeControl, switch: switchControl, choice: choiceControl, days: daysControl })[row.modelData.type] || null

                Component {
                  id: choiceControl
                  ButtonGroup {
                    options: row.modelData.options.map(function(v, i) { return { value: v, label: root.tr(row.modelData.labels[i]) } })
                    value: root.s[row.modelData.key]
                    focusable: false
                    foreground: root.fg
                    fontFamily: root.font
                    onChanged: function(v) { root.set(row.modelData.key, v) }
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
                // Work days and time, as in the Workspaces schedule: ←/→ walk the
                // days, Enter or a click switches one; Enter on a time row types
                // in its field, Enter or Esc gives the keys back, leaving saves.
                Component {
                  id: daysControl
                  Row {
                    spacing: Style.space(4)
                    Repeater {
                      model: L.DAYS
                      Button {
                        required property string modelData
                        required property int index
                        text: root.tr(modelData)
                        selected: root.draft.workDays.indexOf(String(index + 1)) >= 0
                        hasCursor: row.hasCursor && root.dayCol === index
                        horizontalPadding: Style.space(5)
                        foreground: root.fg
                        fontFamily: root.font
                        onClicked: { root.cursor = row.index; root.dayCol = index; root.activate(row.index) }
                      }
                    }
                  }
                }
                Component {
                  id: timeControl
                  TextField {
                    id: field
                    width: Style.space(80)
                    placeholderText: root.tr("HH:MM")
                    text: root.draft[row.modelData.key]
                    maximumLength: 5
                    foreground: root.fg
                    font.family: root.font
                    font.pixelSize: Style.font.body
                    Connections { target: root; function onPressRow(i) { if (i === row.index) field.forceActiveFocus() } }
                    Keys.onEscapePressed: keyCatcher.forceActiveFocus()
                    onAccepted: keyCatcher.forceActiveFocus()
                    onEditingFinished: if (text.trim() !== root.draft[row.modelData.key]) {
                      var c = {}
                      c[row.modelData.key] = text.trim()
                      root.setDraft(c)
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
        }
      }
    }
  }
}
