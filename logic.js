.pragma library
// predmaxim.breaks: everything that needs no QML — settings, the schedule,
// busy checks, exercise choice, history and the streak (node test.js).

var DEFAULTS = {
  enabled: true,
  eyesMin: 30, eyesMax: 50, eyesBreakSeconds: 90,
  bodyEvery: 60, bodySeconds: 420, merge: 15,
  microEnabled: true, microEvery: 20, microSeconds: 20,
  idleThreshold: 60,
  strictness: "hard", postponeCount: 2, postponeMinutes: 5,
  soundEnabled: true, soundVolume: 50,
  calendar: true, meetingNudges: false, meetingNudgeEvery: 25,
  showMinutes: false, silence: true, lockKeys: true,
  exclude: "zoom,teams",
  debug: false
}

var LIMITS = {
  eyesMin: [5, 120], eyesMax: [5, 180], eyesBreakSeconds: [20, 600],
  bodyEvery: [10, 240], bodySeconds: [60, 1800], merge: [0, 60],
  microEvery: [5, 60], microSeconds: [10, 120], idleThreshold: [10, 600],
  postponeCount: [0, 10], postponeMinutes: [1, 30], soundVolume: [0, 100], meetingNudgeEvery: [5, 120]
}

var STRICTNESS = ["hard", "medium", "soft"]

function normalize(entry) {
  var e = entry || {}, out = {}
  for (var k in DEFAULTS) {
    var d = DEFAULTS[k], v = e[k]
    if (typeof d === "number")
      out[k] = typeof v === "number" && isFinite(v) ? Math.min(LIMITS[k][1], Math.max(LIMITS[k][0], Math.round(v))) : d
    else if (typeof d === "boolean")
      out[k] = typeof v === "boolean" ? v : d
    else
      out[k] = typeof v === "string" ? v : d
  }
  if (STRICTNESS.indexOf(out.strictness) < 0) out.strictness = DEFAULTS.strictness
  if (out.eyesMax < out.eyesMin) out.eyesMax = out.eyesMin
  return out
}

// Everything the schedule needs, in seconds. Debug reads minutes as seconds.
function seconds(s) {
  var u = s.debug ? 1 : 60
  return {
    eyesMin: s.eyesMin * u, eyesMax: s.eyesMax * u, eyesBreak: s.eyesBreakSeconds,
    body: s.bodyEvery * u, bodyBreak: s.bodySeconds, merge: s.merge * u,
    micro: s.microEnabled ? s.microEvery * u : 0, microLength: s.microSeconds, microGap: 5 * u,
    idle: s.idleThreshold, postpone: s.postponeMinutes * u,
    nudge: s.meetingNudges ? s.meetingNudgeEvery * u : 0,
    lead: 60, grace: 30, after: 120
  }
}

// The bar widget's entry in shell.json, in whichever section it sits.
function readEntry(text, id) {
  var config
  try { config = JSON.parse(text || "{}") } catch (e) { return null }
  var layout = config && config.bar && config.bar.layout ? config.bar.layout : {}
  for (var section in layout) {
    var list = Array.isArray(layout[section]) ? layout[section] : []
    for (var i = 0; i < list.length; i++)
      if (list[i] && list[i].id === id) return list[i]
  }
  return {}
}

// ------------------------------------------------------------ counters

// Seconds of activity since each need was last met.
function newState() {
  return { eyes: 0, body: 0, micro: 0, snoozeUntil: 0, postponed: 0 }
}

function copy(st) {
  return { eyes: st.eyes, body: st.body, micro: st.micro, snoozeUntil: st.snoozeUntil, postponed: st.postponed }
}

// A need met: a break, a micro-pause, or an absence that long.
function credit(st, kind) {
  var n = copy(st)
  n.micro = 0
  if (kind === "micro") return n
  n.eyes = 0
  if (kind === "body") n.body = 0
  n.snoozeUntil = 0
  n.postponed = 0
  return n
}

// dt seconds have passed; idleSec is how long there has been no input (0: active).
function tick(st, dt, idleSec, c) {
  if (idleSec <= 0) {
    var n = copy(st)
    n.eyes += dt; n.body += dt; n.micro += dt
    return n
  }
  if (idleSec >= c.bodyBreak) return credit(st, "body")
  if (idleSec >= c.eyesBreak) return credit(st, "eyes")
  if (idleSec >= c.microLength) return credit(st, "micro")
  return st
}

// ------------------------------------------------------------ calendar

// Busy time from the Datebook cache; null when the file is broken.
function busyEvents(text) {
  var d
  try { d = JSON.parse(text || "{}") } catch (e) { return null }
  var list = d && Array.isArray(d.events) ? d.events : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i]
    if (!e || e.allDay || e.status === "cancelled" || e.response === "declined") continue
    var start = Date.parse(e.start), end = Date.parse(e.end)
    if (isFinite(start) && isFinite(end) && end > start) out.push({ start: start, end: end, title: String(e.title || "") })
  }
  return out.sort(function(a, b) { return a.start - b.start })
}

function eventAt(events, now) {
  for (var i = 0; events && i < events.length; i++)
    if (events[i].start <= now && now < events[i].end) return events[i]
  return null
}

function nextEvent(events, now) {
  for (var i = 0; events && i < events.length; i++)
    if (events[i].start > now) return events[i]
  return null
}

// ------------------------------------------------------------ schedule

// The next blocking break and the seconds until it. Eyes go at the middle of
// their window unless the body break comes within `merge` of it: then the
// body break takes them, pulled no later than the eye deadline.
function plan(st, c, now, events) {
  var bodyIn = c.body - st.body
  var mid = (c.eyesMin + c.eyesMax) / 2
  // Body due: the long break takes the eyes too, whatever they owe.
  var p = bodyIn <= 0 || bodyIn - (mid - st.eyes) <= c.merge
    ? { kind: "body", in: Math.min(bodyIn, c.eyesMax - st.eyes) }
    : { kind: "eyes", in: mid - st.eyes }
  p.in = Math.max(0, p.in)
  var len = p.kind === "body" ? c.bodyBreak : c.eyesBreak
  // ponytail: only the next meeting is checked; two back-to-back meetings push the break past the first one only
  var next = nextEvent(events, now)
  if (next) {
    var start = (next.start - now) / 1000, end = (next.end - now) / 1000
    var before = start - len - c.lead
    if (p.in > before && p.in < end) {
      var earliest = p.kind === "body" ? c.body - c.merge - st.body : c.eyesMin - st.eyes
      // A break that no longer fits before the meeting goes after it.
      p.in = before >= 0 && before >= earliest ? before : end + c.after
    }
  }
  if (st.snoozeUntil > now) p.in = Math.max(p.in, (st.snoozeUntil - now) / 1000)
  p.in = Math.max(0, p.in)
  return p
}

// What to do this second. ctx: events (null: no calendar), busy (sensors),
// freeFor (seconds since nothing blocks), afterEvent (the last block was a meeting).
function decide(st, c, now, ctx) {
  var p = plan(st, c, now, ctx.events)
  var blocked = ctx.busy || eventAt(ctx.events, now) !== null
  if (p.in <= 0) {
    if (blocked || ctx.freeFor < (ctx.afterEvent ? c.after : c.grace)) return { action: "wait", kind: p.kind, in: 0 }
    return { action: "break", kind: p.kind, in: 0 }
  }
  if (c.micro && st.micro >= c.micro && p.in >= c.microGap && !blocked) return { action: "micro", kind: p.kind, in: p.in }
  if (p.in <= c.lead && !blocked) return { action: "warn", kind: p.kind, in: p.in }
  return { action: "none", kind: p.kind, in: p.in }
}

// Postponed by postponeMinutes, at most postponeCount times per break.
function postpone(st, c, s, now) {
  if (st.postponed >= s.postponeCount) return null
  var n = copy(st)
  n.postponed++
  n.snoozeUntil = now + c.postpone * 1000
  return n
}

// No skipping in hard mode.
function skip(st, kind, s) {
  return s.strictness === "hard" ? null : credit(st, kind)
}

// ------------------------------------------------------------ meetings

var NUDGES = [
  "Stand up for the rest of the call",
  "25 calf raises while you listen",
  "10 squats with the camera off",
  "Look out of the window for 20 seconds",
  "Roll your shoulders back 10 times"
]

var TIPS = [
  "Drink a glass of water",
  "Go to the window: daylight is good for the eyes",
  "Walk to the kitchen and back"
]

// Every `nudge` seconds of a meeting, counted from its start or the last nudge.
function nudgeDue(event, now, last, c) {
  if (!c.nudge || !event) return false
  return now - Math.max(event.start, last) >= c.nudge * 1000
}

// ------------------------------------------------------------ sensors

// A capture stream that is not muted: someone is recording the microphone.
// The same test as the shell's microphone widget.
function micBusy(nodes) {
  for (var i = 0; nodes && i < nodes.length; i++) {
    var n = nodes[i]
    if (n && n.isStream && n.isSink === false && !(n.audio && n.audio.muted)) return true
  }
  return false
}

function excluded(cls, list) {
  var c = String(cls || "").toLowerCase()
  if (!c) return false
  return String(list || "").split(",").some(function(x) { x = x.trim().toLowerCase(); return x !== "" && c.indexOf(x) >= 0 })
}

// `hyprctl activewindow -j`, "@@", then "cam" when a /dev/video* is open.
// Hyprland's fullscreen: 0 none, 1 maximized, 2 fullscreen.
function parseProbe(text) {
  var parts = String(text || "").split("@@")
  var win = {}
  try { win = JSON.parse(parts[0]) || {} } catch (e) { win = {} }
  return {
    fullscreen: win.fullscreen === true || win.fullscreen >= 2,
    cls: String(win.class || ""),
    camera: parts.length > 1 && parts[1].indexOf("cam") >= 0
  }
}

// ------------------------------------------------------------ exercises

// One QML file per eye exercise (they differ); body steps share BodyStep.qml.
var EXERCISES = [
  { id: "saccades", category: "eyes", title: "Catch the dot", file: "Saccades.qml", seconds: 40, needsInput: true },
  { id: "eight", category: "eyes", title: "Follow the figure eight", file: "Eight.qml", seconds: 40, needsInput: false },
  { id: "farNumber", category: "eyes", title: "Look far away", file: "FarNumber.qml", seconds: 30, needsInput: true },
  { id: "nearFar", category: "eyes", title: "Near and far", file: "NearFar.qml", seconds: 40, needsInput: false },
  { id: "palming", category: "eyes", title: "Palming", file: "Palming.qml", seconds: 45, needsInput: false },
  { id: "blink", category: "eyes", title: "Slow blinks", file: "Blink.qml", seconds: 30, needsInput: false },
  { id: "squats", category: "body", title: "Squats", file: "BodyStep.qml", reps: 15, perRep: 3, needsInput: false },
  { id: "calves", category: "body", title: "Calf raises", file: "BodyStep.qml", reps: 25, perRep: 2, needsInput: false },
  { id: "shoulders", category: "body", title: "Shoulder rolls", file: "BodyStep.qml", reps: 10, perRep: 4, needsInput: false },
  { id: "neck", category: "body", title: "Neck turns", file: "BodyStep.qml", reps: 6, perRep: 5, needsInput: false },
  { id: "hips", category: "body", title: "Hip flexor stretch, each side", file: "BodyStep.qml", reps: 4, perRep: 10, needsInput: false },
  { id: "plank", category: "body", title: "Plank", file: "BodyStep.qml", seconds: 40, needsInput: false },
  { id: "breath478", category: "breath", title: "Breathing 4-7-8", file: "Breath.qml", pattern: [4, 7, 8, 0], seconds: 76, needsInput: false },
  { id: "breathBox", category: "breath", title: "Box breathing", file: "Breath.qml", pattern: [4, 4, 4, 4], seconds: 64, needsInput: false }
]

// +1 rep every 3 days of streak, up to twice the base.
function reps(base, days) {
  return Math.min(base * 2, base + Math.floor(days / 3))
}

function takeOne(category, avoid, days, rnd) {
  var pool = EXERCISES.filter(function(e) { return e.category === category && avoid.indexOf(e.id) < 0 })
  if (pool.length === 0) pool = EXERCISES.filter(function(e) { return e.category === category })
  var e = pool[Math.floor(rnd() * pool.length) % pool.length]
  avoid.push(e.id)
  var n = e.reps ? reps(e.reps, days) : 0
  return { id: e.id, category: e.category, title: e.title, file: e.file, needsInput: e.needsInput,
    reps: n, seconds: e.reps ? n * e.perRep : e.seconds, pattern: e.pattern || null }
}

// Eyes: one exercise, two when the break is 80 s or longer. Body: two body
// steps (the second is breathing on odd streak days) and one for the eyes.
// Nothing from the last break repeats.
function pickBreak(kind, c, lastIds, days, rnd) {
  var avoid = (lastIds || []).slice()
  rnd = rnd || Math.random
  var one = function(category) { return takeOne(category, avoid, days, rnd) }
  if (kind === "eyes") return c.eyesBreak >= 80 ? [one("eyes"), one("eyes")] : [one("eyes")]
  return [one("body"), one(days % 2 ? "breath" : "body"), one("eyes")]
}

// ------------------------------------------------------------ history

function pad(n) { return n < 10 ? "0" + n : String(n) }

function dayKey(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function parseHistory(text) {
  var out = []
  String(text || "").split("\n").forEach(function(line) {
    if (!line.trim()) return
    try { var h = JSON.parse(line); if (h && typeof h.ts === "number") out.push(h) } catch (e) {}
  })
  return out
}

// Days in a row with a finished break; a skip breaks the streak, a day not
// over yet does not.
function streak(history, now) {
  var good = {}, bad = {}
  history.forEach(function(h) {
    var k = dayKey(h.ts)
    if (h.skipped) bad[k] = true
    else if (h.completed) good[k] = true
  })
  var d = new Date(now)
  if (bad[dayKey(now)]) return 0
  if (!good[dayKey(now)]) d.setDate(d.getDate() - 1)
  var n = 0
  while (good[dayKey(d.getTime())] && !bad[dayKey(d.getTime())]) { n++; d.setDate(d.getDate() - 1) }
  return n
}

function todayStats(history, now) {
  var today = dayKey(now), out = { breaks: 0, reps: {} }
  history.forEach(function(h) {
    if (!h.completed || h.kind === "micro" || dayKey(h.ts) !== today) return
    out.breaks++
    ;(h.exercises || []).forEach(function(e) { if (e.reps) out.reps[e.id] = (out.reps[e.id] || 0) + e.reps })
  })
  return out
}

// ------------------------------------------------------------ panel rows

// The modal's rows, walked with ↑/↓, the header first (main: on/off and
// settings buttons; settings: Back). Page "main": the actions and the
// everyday switches; page "settings": the rest. Labels are English, for tr().
function rowsFor(page, s) {
  if (page === "settings") {
    var rows = [
      { type: "head" },
      { type: "num", key: "eyesMin", label: "Eyes: no earlier than, min", step: 5 },
      { type: "num", key: "eyesMax", label: "Eyes: no later than, min", step: 5 },
      { type: "num", key: "bodyEvery", label: "Body: every, min", step: 5 }
    ]
    if (s.microEnabled) rows.push({ type: "num", key: "microEvery", label: "Micro-pause every, min", step: 5 })
    rows.push({ type: "num", key: "postponeCount", label: "Postpones per break", step: 1 })
    if (s.soundEnabled) rows.push({ type: "num", key: "soundVolume", label: "Volume, %", step: 10 })
    rows.push({ type: "switch", key: "lockKeys", label: "Block hotkeys during breaks" },
      { type: "switch", key: "showMinutes", label: "Minutes in the bar" },
      { type: "switch", key: "debug", label: "Debug" })
    return rows
  }
  var main = [{ type: "head" }, { type: "choice", key: "strictness", label: "Strictness", options: STRICTNESS }]
  if (s.strictness !== "hard" || s.debug) main.push({ type: "action", key: "pause", label: "Pause 1 h" })
  main.push({ type: "switch", key: "soundEnabled", label: "Sounds" },
    { type: "switch", key: "silence", label: "Silence during breaks" },
    { type: "switch", key: "calendar", label: "Respect the calendar" },
    { type: "switch", key: "meetingNudges", label: "Movement tips during meetings" },
    { type: "switch", key: "microEnabled", label: "Micro-pauses 20-20-20" })
  return main
}

// ←/→ (dx = -1/1) on a row: the new value, or null when nothing changes.
function adjust(row, s, dx) {
  if (!row || !row.key) return null
  var v = s[row.key]
  if (row.type === "switch") return { key: row.key, value: !v }
  if (row.type === "choice") {
    var o = row.options, i = (o.indexOf(v) + dx + o.length) % o.length
    return { key: row.key, value: o[i] }
  }
  if (row.type === "num") {
    var n = Math.min(LIMITS[row.key][1], Math.max(LIMITS[row.key][0], v + dx * row.step))
    return n === v ? null : { key: row.key, value: n }
  }
  return null
}
