import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import "logic.js" as L
import "I18n.js" as I18n

// predmaxim.breaks: breaks by active time (logic.js decides). Every second it
// reads the sensors — idle, microphone, camera, fullscreen, the Datebook
// calendar — and opens Overlay.qml (a break) or Micro.qml (a micro-pause).
// Settings are the bar widget's entry in shell.json (schema in manifest.json).
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "predmaxim.breaks"
  readonly property string home: Quickshell.env("HOME")
  readonly property string historyPath: home + "/.local/state/predmaxim-breaks/history.jsonl"
  readonly property var tr: I18n.translator(I18n.textLanguage(Quickshell.env))

  property var settings: L.normalize({})
  readonly property var c: L.seconds(settings)
  property var st: L.newState()
  property var events: null
  property var history: []
  property var decision: ({ action: "none", kind: "eyes", in: 0 })

  // A break in progress: Overlay.qml is up while breakSteps is not empty.
  property var breakSteps: []
  property string breakKind: ""
  property bool microShown: false
  property bool warned: false
  property real lastNudge: 0

  // ------------------------------------------------------------ settings and files

  // From the widget's panel: merged, checked, stored in the bar widget's entry.
  function store(changes) {
    var entry = {}
    for (var k in root.settings) entry[k] = root.settings[k]
    for (var c in changes) entry[c] = changes[c]
    root.settings = L.normalize(entry)
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.pluginId, root.settings)
  }

  FileView {
    path: root.home + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var entry = L.readEntry(text(), root.pluginId)
      if (entry === null) console.warn("predmaxim.breaks: could not read shell.json")
      else root.settings = L.normalize(entry)
    }
  }

  FileView {
    path: root.home + "/.cache/predmaxim.datebook/events.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.events = L.busyEvents(text())
      if (root.events === null) console.warn("predmaxim.breaks: the calendar cache is broken, working without it")
    }
  }

  FileView {
    path: root.historyPath
    printErrors: false
    onLoaded: root.history = L.parseHistory(text())
  }

  function record(entry) {
    root.history = root.history.concat([entry])
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" >> "$1"',
      "sh", root.historyPath, JSON.stringify(entry)])
  }

  // ------------------------------------------------------------ sensors

  // Respecting inhibitors: idle in rawIdle but not here means something
  // inhibits idle (video, Omarchy's idle toggle) — a reason to wait.
  IdleMonitor {
    id: idle
    timeout: root.settings.idleThreshold
    respectInhibitors: true
  }
  // Ignoring them: no input. Away counts as a break unless media is playing
  // (watching is work for the eyes); a stuck inhibitor does not hide an absence.
  IdleMonitor {
    id: rawIdle
    timeout: root.settings.idleThreshold
    respectInhibitors: false
    onIsIdleChanged: root.idleSince = isIdle ? Date.now() - timeout * 1000 : 0
  }
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property bool mediaPlaying: players.some(function(p) { return p && p.isPlaying })
  // A micro-pause is done after microSeconds without input.
  IdleMonitor {
    enabled: root.microShown
    timeout: root.settings.microSeconds
    respectInhibitors: false
    onIsIdleChanged: if (isIdle && root.microShown) root.finishMicro(true)
  }

  property real idleSince: 0

  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  PwObjectTracker { objects: root.nodes }

  property var probe: ({ fullscreen: false, cls: "", camera: false })
  Process {
    id: prober
    command: ["sh", "-c", "hyprctl activewindow -j; echo '@@'; for d in /dev/video*; do [ -e \"$d\" ] && fuser -s \"$d\" 2>/dev/null && { echo cam; break; }; done"]
    stdout: StdioCollector { onStreamFinished: root.probe = L.parseProbe(text) }
  }
  Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: prober.running = true }

  // Why a break has to wait; "" when nothing is in the way.
  readonly property string busyReason: L.micBusy(nodes) ? "microphone"
    : probe.camera ? "camera"
    : (rawIdle.isIdle && !idle.isIdle) ? "video"
    : probe.fullscreen ? "fullscreen"
    : L.excluded(probe.cls, settings.exclude) ? "app"
    : ""

  // ------------------------------------------------------------ the loop

  property real lastStep: Date.now()
  property real freeSince: Date.now()
  property bool lastBlockEvent: false

  Timer { interval: 1000; running: true; repeat: true; onTriggered: root.step() }

  function step() {
    var now = Date.now(), gap = (now - root.lastStep) / 1000
    root.lastStep = now
    if (root.breakSteps.length > 0) return
    // Turned off: nothing counts and nothing comes.
    if (!root.settings.enabled) {
      if (root.microShown) root.finishMicro(false)
      return
    }
    // A gap longer than the idle threshold is sleep: an absence, not work (Review Focus 1).
    if (gap > root.c.idle) root.st = L.tick(root.st, 0, gap, root.c)
    var idleSec = root.idleSince > 0 && !root.mediaPlaying ? (now - root.idleSince) / 1000 : 0
    root.st = L.tick(root.st, Math.min(gap, 5), idleSec, root.c)

    var ev = root.settings.calendar ? root.events : null
    var current = L.eventAt(ev, now)
    if (root.busyReason !== "" || current) {
      root.freeSince = 0
      root.lastBlockEvent = current !== null
    } else if (root.freeSince === 0) root.freeSince = now

    root.decision = L.decide(root.st, root.c, now, {
      events: ev, busy: root.busyReason !== "",
      freeFor: root.freeSince ? (now - root.freeSince) / 1000 : 0,
      afterEvent: root.lastBlockEvent
    })

    if (L.nudgeDue(current, now, root.lastNudge, root.c)) {
      root.lastNudge = now
      root.notify(root.tr(L.NUDGES[Math.floor(Math.random() * L.NUDGES.length)]))
    }

    var a = root.decision.action
    if (a === "break") root.startBreak(root.decision.kind)
    else if (a === "micro" && !root.microShown) { root.microShown = true; microTimeout.restart(); root.sound("micro") }
    else if (a === "warn" && !root.warned) { root.warned = true; root.notify(root.tr("Break in a minute")) }
  }

  // ------------------------------------------------------------ breaks

  function lastIds() {
    for (var i = root.history.length - 1; i >= 0; i--)
      if (root.history[i].kind !== "micro") return (root.history[i].exercises || []).map(function(e) { return e.id })
    return []
  }

  function startBreak(kind) {
    root.microShown = false
    root.warned = false
    root.breakKind = kind
    root.breakSteps = L.pickBreak(kind, root.c, root.lastIds(), L.streak(root.history, Date.now()), Math.random)
    root.sound("start")
  }

  // reason: done | skip | abort. The need counts as met either way, so an
  // aborted break does not come straight back.
  function finishBreak(reason) {
    if (root.breakSteps.length === 0) return
    root.record({ ts: Date.now(), kind: root.breakKind,
      exercises: root.breakSteps.map(function(s) { return { id: s.id, reps: s.reps } }),
      completed: reason === "done", skipped: reason === "skip", reason: reason, postponed: root.st.postponed })
    root.st = L.credit(root.st, root.breakKind)
    root.breakSteps = []
    root.breakKind = ""
  }

  function postponeBreak() {
    var n = L.postpone(root.st, root.c, root.settings, Date.now())
    if (!n) return false
    root.st = n
    root.breakSteps = []
    root.breakKind = ""
    return true
  }

  function skipBreak() {
    if (L.skip(root.st, root.breakKind, root.settings) === null) return false
    root.finishBreak("skip")
    return true
  }

  // Shown for 3 minutes at most, a reminder sound every minute.
  Timer { id: microTimeout; interval: 180000; onTriggered: root.finishMicro(false) }
  Timer { interval: 60000; repeat: true; running: root.microShown; onTriggered: root.sound("micro") }

  function finishMicro(done) {
    if (!root.microShown) return
    root.microShown = false
    microTimeout.stop()
    if (done) root.sound("end")
    root.st = L.credit(root.st, "micro")
    root.record({ ts: Date.now(), kind: "micro", completed: done })
  }

  // Pause the schedule; not in hard mode unless debugging.
  function pause(minutes) {
    if (root.settings.strictness === "hard" && !root.settings.debug) return false
    var n = JSON.parse(JSON.stringify(root.st))
    n.snoozeUntil = Date.now() + minutes * 60000
    root.st = n
    return true
  }

  // ------------------------------------------------------------ output

  // For the icon among the bar's indicators (Indicator.qml): on or off,
  // minutes to the next break and what it is. Written when it changes.
  readonly property string indicatorState: JSON.stringify({
    enabled: root.settings.enabled,
    showMinutes: root.settings.showMinutes,
    minutes: Math.ceil(root.decision.in / 60),
    kind: root.decision.kind,
    busy: root.busyReason
  })
  onIndicatorStateChanged: Quickshell.execDetached(["sh", "-c", 'printf "%s" "$1" > "$XDG_RUNTIME_DIR/predmaxim-breaks.json"', "sh", root.indicatorState])

  readonly property var cues: ({ start: "bell", micro: "window-attention", step: "message", end: "complete" })
  function sound(cue) {
    if (!root.settings.soundEnabled) return
    Quickshell.execDetached(["pw-play", "--volume=" + (root.settings.soundVolume / 100),
      "/usr/share/sounds/freedesktop/stereo/" + root.cues[cue] + ".oga"])
  }

  function notify(text) {
    Quickshell.execDetached(["omarchy-notification-send", "-u", "normal", root.tr("Breaks"), text])
  }

  Overlay { service: root }
  Micro { service: root }

  // ------------------------------------------------------------ IPC

  IpcHandler {
    target: "predmaxim.breaks"

    function status(): string {
      return JSON.stringify({ state: root.st, decision: root.decision, busy: root.busyReason,
        inBreak: root.breakSteps.length > 0, micro: root.microShown, idleSince: root.idleSince,
        events: root.events ? root.events.length : null, settings: root.settings })
    }
    // Always works, whatever the strictness: the way out.
    function abort(): string {
      if (root.microShown) root.finishMicro(false)
      if (root.breakSteps.length === 0) return "no break"
      root.finishBreak("abort")
      return "ok"
    }
    function now(kind: string): string {
      if (root.breakSteps.length > 0) return "already"
      root.startBreak(kind === "body" ? "body" : "eyes")
      return "ok"
    }
    function pause(minutes: string): string {
      return root.pause(Number(minutes) || 60) ? "ok" : "not in hard mode"
    }
  }
}
