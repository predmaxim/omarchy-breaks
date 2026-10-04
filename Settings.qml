import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "logic.js" as L
import "I18n.js" as I18n

// predmaxim.breaks settings: a floating window (Super+W or Esc closes it).
// Changes go through the service into the bar widget's entry in shell.json
// and apply at once. Open: a click on the bar widget, or
// `omarchy-shell predmaxim.breaks settings`.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null
  property var service: null

  property bool closingFromHost: false
  readonly property var tr: I18n.translator(I18n.textLanguage(Quickshell.env))
  readonly property var s: service ? service.settings : L.normalize({})
  readonly property color foreground: Color.menu.text
  readonly property int pad: Style.spacing.panelPadding

  function open(payloadJson) {
    root.closingFromHost = false
    window.visible = true
    Qt.callLater(function() { if (window.visible) keys.forceActiveFocus() })
    raise.restart()
  }

  function close() {
    root.closingFromHost = true
    window.visible = false
    root.closingFromHost = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide("predmaxim.breaks")
    else close()
  }

  function set(key, value) {
    var change = {}
    change[key] = value
    if (root.service) root.service.store(change)
  }

  // The window may open behind others; ask Hyprland to focus it.
  Timer {
    id: raise
    interval: 120
    onTriggered: if (window.visible) Quickshell.execDetached(["hyprctl", "eval",
      "hl.dispatch(hl.dsp.focus({ window = " + JSON.stringify("title:^" + window.title + "$") + " }))"])
  }

  component Section: Text {
    Layout.topMargin: Style.space(8)
    color: Color.accent
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  component Num: NumberField {
    property string key
    Layout.fillWidth: true
    value: root.s[key]
    from: L.LIMITS[key][0]
    to: L.LIMITS[key][1]
    foreground: root.foreground
    onModified: function(v) { root.set(key, v) }
  }

  component Flag: Toggle {
    property string key
    Layout.fillWidth: true
    checked: root.s[key]
    foreground: root.foreground
    onClicked: root.set(key, !root.s[key])
  }

  FloatingWindow {
    id: window
    title: root.tr("Breaks")
    visible: false
    color: Color.menu.background
    implicitWidth: Style.space(480)
    implicitHeight: Math.min(Style.space(760), content.implicitHeight + root.pad * 2)
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)

    // Closed by the compositor (Super+W): tell the shell, so it opens again next time.
    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("predmaxim.breaks")
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      Flickable {
        anchors.fill: parent
        anchors.margins: root.pad
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
          id: content
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: root.tr("Breaks")
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          RowLayout {
            spacing: Style.space(8)
            Button {
              text: root.tr("Break now")
              foreground: root.foreground
              bordered: true
              onClicked: { root.dismiss(); if (root.service) root.service.startBreak(root.service.decision.kind) }
            }
            Button {
              visible: root.s.strictness !== "hard" || root.s.debug
              text: root.tr("Pause 1 h")
              foreground: root.foreground
              bordered: true
              onClicked: if (root.service) root.service.pause(60)
            }
          }

          Section { text: root.tr("Strictness") }
          ButtonGroup {
            options: [{ value: "hard", label: root.tr("Hard") }, { value: "medium", label: root.tr("Medium") }, { value: "soft", label: root.tr("Soft") }]
            value: root.s.strictness
            foreground: root.foreground
            onChanged: function(v) { root.set("strictness", v) }
          }
          Num { key: "postponeCount"; label: root.tr("Postpones per break") }
          Num { key: "postponeMinutes"; label: root.tr("Postpone by, min") }

          Section { text: root.tr("Eyes") }
          Num { key: "eyesMin"; label: root.tr("Break no earlier than, min") }
          Num { key: "eyesMax"; label: root.tr("Break no later than, min") }
          Num { key: "eyesBreakSeconds"; label: root.tr("Break length, s") }
          Flag { key: "microEnabled"; label: root.tr("Micro-pauses 20-20-20") }
          Num { key: "microEvery"; label: root.tr("Micro-pause every, min") }
          Num { key: "microSeconds"; label: root.tr("Micro-pause length, s") }

          Section { text: root.tr("Body") }
          Num { key: "bodyEvery"; label: root.tr("Break every, min") }
          Num { key: "bodySeconds"; label: root.tr("Break length, s") }
          Num { key: "merge"; label: root.tr("Join eyes into it within, min") }

          Section { text: root.tr("Do not disturb") }
          Flag { key: "calendar"; label: root.tr("Respect the calendar") }
          Flag { key: "meetingNudges"; label: root.tr("Movement tips during meetings") }
          Num { key: "meetingNudgeEvery"; label: root.tr("Meeting tip every, min") }
          Text {
            text: root.tr("Never interrupt these apps (window classes, comma separated)")
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          TextField {
            Layout.fillWidth: true
            text: root.s.exclude
            foreground: root.foreground
            font.family: Style.font.family
            onEditingFinished: root.set("exclude", text)
          }
          Num { key: "idleThreshold"; label: root.tr("Idle after, s") }

          Section { text: root.tr("Sound") }
          Flag { key: "soundEnabled"; label: root.tr("Sounds") }
          Num { key: "soundVolume"; label: root.tr("Volume, %") }

          Flag { key: "debug"; label: root.tr("Debug"); description: root.tr("Minutes become seconds; Super+Ctrl+Alt+Esc ends a break.") }

          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Style.space(6)
            Item { Layout.fillWidth: true }
            Button {
              text: root.tr("Done")
              foreground: root.foreground
              bordered: true
              onClicked: root.dismiss()
            }
          }
        }
      }
    }
  }
}
