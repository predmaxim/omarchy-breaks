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
// the screen like todo's: on/off, what comes next, "break now" and "pause", the
// everyday settings in three tabs. Rare ones (break lengths, idle threshold…)
// stay in shell.json. Settings are written by the service into this entry.
Panel {
  id: root
  moduleName: "predmaxim.breaks"
  ipcTarget: "predmaxim.breaks-panel"

  readonly property var tr: I18n.translator(I18n.textLanguage(Quickshell.env))
  property var service: null
  property string tab: "schedule"

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
  readonly property string icon: "󰥔"
  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string font: Style.font.family

  readonly property string nextText: !service ? ""
    : service.busyReason ? tr("Waiting: %1", tr(service.busyReason))
    : tr(d.kind === "body" ? "Next: body in %1 min" : "Next: eyes in %1 min", minutes)
  readonly property var today: service ? L.todayStats(service.history, Date.now()) : ({ breaks: 0, reps: {} })
  readonly property int streak: service ? L.streak(service.history, Date.now()) : 0

  function set(key, value) {
    var change = {}
    change[key] = value
    if (root.service) root.service.store(change)
  }

  visible: false
  implicitWidth: 0
  implicitHeight: 0

  // One settings row: the label on the left, the control on the right.
  component Line: RowLayout {
    id: line
    property string label
    default property alias control: slot.data
    Layout.fillWidth: true
    Text {
      Layout.fillWidth: true
      text: line.label
      color: root.fg
      font.family: root.font
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
    Item { id: slot; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
  }

  component Num: NumberField {
    property string key
    value: root.s[key]
    from: L.LIMITS[key][0]
    to: L.LIMITS[key][1]
    foreground: root.fg
    onModified: function(v) { root.set(key, v) }
  }

  component Switch: ToggleSwitch {
    property string key
    checked: root.s[key]
    foreground: root.fg
    onToggled: root.set(key, !root.s[key])
  }

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
      width: Math.min(Style.space(420), modal.width - Style.space(80))
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
      onCloseRequested: root.close()

      ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        PanelHero {
          Layout.fillWidth: true
          title: root.tr("Breaks")
          meta: root.s.enabled ? root.nextText : root.tr("Breaks are off")
          foreground: root.fg
          fontFamily: root.font
          iconComponent: Text {
            text: root.icon
            color: root.fg
            font.family: root.font
            font.pixelSize: Style.font.display
          }
          // On/off: off stops the counters and every break.
          trailingControl: ToggleSwitch {
            checked: root.s.enabled
            foreground: root.fg
            onToggled: root.set("enabled", !root.s.enabled)
          }
        }

        Text {
          text: [root.tr("Today: %1 breaks", root.today.breaks), root.tr("Streak: %1 days", root.streak)].join(" · ").toUpperCase()
          color: root.dim
          font.family: root.font
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }

        RowLayout {
          spacing: Style.space(8)
          Button {
            text: root.tr("Break now")
            foreground: root.fg
            fontFamily: root.font
            bordered: true
            onClicked: { root.close(); if (root.service) root.service.startBreak(root.d.kind) }
          }
          Button {
            visible: root.s.strictness !== "hard" || root.s.debug
            text: root.tr("Pause 1 h")
            foreground: root.fg
            fontFamily: root.font
            bordered: true
            onClicked: if (root.service) root.service.pause(60)
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.fg }

        ButtonGroup {
          options: [{ value: "schedule", label: root.tr("Schedule") }, { value: "mode", label: root.tr("Mode") }, { value: "sound", label: root.tr("Sound") }]
          value: root.tab
          foreground: root.fg
          fontFamily: root.font
          onChanged: function(v) { root.tab = v }
        }

        ColumnLayout {
          visible: root.tab === "schedule"
          Layout.fillWidth: true
          spacing: Style.space(6)
          Line { label: root.tr("Eyes: no earlier than, min"); Num { key: "eyesMin" } }
          Line { label: root.tr("Eyes: no later than, min"); Num { key: "eyesMax" } }
          Line { label: root.tr("Body: every, min"); Num { key: "bodyEvery" } }
          Line { label: root.tr("Micro-pauses 20-20-20"); Switch { key: "microEnabled" } }
          Line { label: root.tr("Micro-pause every, min"); visible: root.s.microEnabled; Num { key: "microEvery" } }
        }

        ColumnLayout {
          visible: root.tab === "mode"
          Layout.fillWidth: true
          spacing: Style.space(6)
          ButtonGroup {
            options: [{ value: "hard", label: root.tr("Hard") }, { value: "medium", label: root.tr("Medium") }, { value: "soft", label: root.tr("Soft") }]
            value: root.s.strictness
            foreground: root.fg
            fontFamily: root.font
            onChanged: function(v) { root.set("strictness", v) }
          }
          Line { label: root.tr("Postpones per break"); Num { key: "postponeCount" } }
          Line { label: root.tr("Respect the calendar"); Switch { key: "calendar" } }
          Line { label: root.tr("Movement tips during meetings"); Switch { key: "meetingNudges" } }
          Line { label: root.tr("Debug"); Switch { key: "debug" } }
        }

        ColumnLayout {
          visible: root.tab === "sound"
          Layout.fillWidth: true
          spacing: Style.space(6)
          Line { label: root.tr("Sounds"); Switch { key: "soundEnabled" } }
          Line { label: root.tr("Volume, %"); visible: root.s.soundEnabled; Num { key: "soundVolume" } }
        }
      }
    }
  }
    }
  }
