import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "logic.js" as L

// The break: a fullscreen layer on every monitor. The focused one gets the
// keyboard and the exercise; the others just ask to look there. Any input
// during a step that needs none pauses it: the break counts only away from
// the keyboard.
Item {
  id: root
  property var service: null
  readonly property var s: service
  readonly property bool open: s !== null && s.breakSteps.length > 0
  readonly property string mainScreen: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

  property int index: 0
  property real remaining: 0
  property real touchedAt: 0
  property real stepAt: 0
  property real zeroAt: 0
  readonly property var step: open && index < s.breakSteps.length ? s.breakSteps[index] : null
  // Date.now() is not a binding dependency: `clock` ticks so `paused` clears.
  property real clock: Date.now()
  readonly property bool paused: step !== null && !step.needsInput && clock - touchedAt < 3000
  property bool summary: false

  onOpenChanged: if (open) { index = 0; summary = false; remaining = s.breakSteps[0].seconds; stepAt = Date.now(); touchedAt = 0 }

  // The hover event a new window gets on appearing is not a touch: 1.5 s grace per step.
  function touched() { if (step && !step.needsInput && Date.now() - stepAt > 1500) touchedAt = Date.now() }
  function next() {
    if (index + 1 < s.breakSteps.length) {
      index++
      remaining = s.breakSteps[index].seconds
      stepAt = Date.now()
      s.sound("step")
    } else { summary = true; s.sound("end") }
  }

  Timer {
    interval: 1000; repeat: true; running: root.open && !root.summary
    onTriggered: {
      root.clock = Date.now()
      if (root.paused) return
      root.remaining = Math.max(0, root.remaining - 1)
      if (root.remaining > 0) root.zeroAt = root.clock
      if (root.remaining > 0 || !root.step) return
      // An input step ends itself; if it never does (failed to load, no answer), 20 s later.
      if (!root.step.needsInput || root.clock - root.zeroAt > 20000) root.next()
    }
  }
  // The summary card stays 8 s, then the break is done.
  Timer { interval: 8000; running: root.summary; onTriggered: root.s.finishBreak("done") }

  Variants {
    model: root.open ? Quickshell.screens : []
    delegate: Component {
      PanelWindow {
        id: win
        required property var modelData
        readonly property bool main: modelData.name === root.mainScreen
        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
        WlrLayershell.namespace: "predmaxim-breaks"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: win.main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onPositionChanged: root.touched()
          onPressed: root.touched()
        }

        Item {
          anchors.fill: parent
          focus: win.main
          Keys.onPressed: function(event) {
            if (root.s.settings.debug && event.key === Qt.Key_Escape
                && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.AltModifier) && (event.modifiers & Qt.MetaModifier)) {
              root.s.finishBreak("abort"); event.accepted = true; return
            }
            if (!root.step || !root.step.needsInput) { root.touched(); event.accepted = true }
          }

          Text {
            visible: !win.main
            anchors.centerIn: parent
            text: root.s.tr("Look at the main screen")
            color: Color.foreground; font.pixelSize: 28
          }

          Column {
            visible: win.main && !root.summary
            anchors.fill: parent
            anchors.margins: 48
            spacing: 16

            Text {
              text: root.s.tr(root.s.breakKind === "body" ? "Break for the body" : "Break for the eyes")
                + "  ·  " + (root.index + 1) + "/" + root.s.breakSteps.length
              color: Color.muted; font.pixelSize: 18
            }
            Text {
              text: root.step ? root.s.tr(root.step.title) : ""
              color: Color.foreground; font.pixelSize: 40; font.bold: true
            }
            Text {
              text: root.paused ? root.s.tr("Hands off: step away from the keyboard") : Math.ceil(root.remaining) + " s"
              color: root.paused ? Color.urgent : Color.accent; font.pixelSize: 22
            }
            Loader {
              id: exercise
              // One copy, on the focused monitor: two would finish twice and pick two digits.
              active: win.main
              width: parent.width
              height: parent.height - 220
              source: root.step ? "exercises/" + root.step.file : ""
              onLoaded: {
                item.step = Qt.binding(function() { return root.step })
                item.tr = root.s.tr
                item.accent = Color.accent
                item.fg = Color.foreground
                item.remaining = Qt.binding(function() { return root.remaining })
                item.focus = true
              }
              Connections {
                target: exercise.item
                ignoreUnknownSignals: true
                function onFinished() { if (root.step && root.step.needsInput) root.next() }
              }
            }
            Row {
              spacing: 16
              Button2 {
                visible: root.s.st.postponed < root.s.settings.postponeCount
                label: root.s.tr("Postpone %1 min", root.s.settings.postponeMinutes)
                onClicked: root.s.postponeBreak()
              }
              Button2 {
                visible: root.s.settings.strictness !== "hard"
                label: root.s.tr("Skip")
                onClicked: root.s.skipBreak()
              }
            }
          }

          Column {
            visible: win.main && root.summary
            anchors.centerIn: parent
            spacing: 12
            readonly property var stats: L.todayStats(root.s.history.concat([{ ts: Date.now(), kind: root.s.breakKind, completed: true,
              exercises: root.s.breakSteps.map(function(x) { return { id: x.id, reps: x.reps } }) }]), Date.now())
            Text { text: root.s.tr("Done"); color: Color.accent; font.pixelSize: 40; font.bold: true }
            Text { text: root.s.tr("Today: %1 breaks", parent.stats.breaks); color: Color.foreground; font.pixelSize: 22 }
            Text {
              text: Object.keys(parent.stats.reps).map(function(k) {
                var e = L.EXERCISES.filter(function(x) { return x.id === k })[0]
                return root.s.tr(e ? e.title : k) + ": " + parent.stats.reps[k]
              }).join("  ·  ")
              color: Color.foreground; font.pixelSize: 18
            }
            Text { text: root.s.tr("Streak: %1 days", L.streak(root.s.history, Date.now()) + 1); color: Color.muted; font.pixelSize: 18 }
            Text { text: root.s.tr(L.TIPS[Math.floor(Math.random() * L.TIPS.length)]); color: Color.muted; font.pixelSize: 18 }
          }
        }
      }
    }
  }

  component Button2: Rectangle {
    property string label
    signal clicked()
    width: t.implicitWidth + 32; height: 40; radius: 6
    color: "transparent"; border.color: Color.muted
    Text { id: t; anchors.centerIn: parent; text: parent.label; color: Color.foreground; font.pixelSize: 16 }
    MouseArea { anchors.fill: parent; onClicked: parent.clicked() }
  }
}
