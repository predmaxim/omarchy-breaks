.pragma library
// predmaxim.breaks: everything that needs no QML — settings, the schedule,
// busy checks, exercise choice, history and the streak (node test.js).

var DEFAULTS = {
  eyesMin: 30, eyesMax: 50, eyesBreakSeconds: 90,
  bodyEvery: 60, bodySeconds: 420, merge: 15,
  microEnabled: true, microEvery: 20, microSeconds: 20,
  idleThreshold: 60,
  strictness: "hard", postponeCount: 2, postponeMinutes: 5,
  soundEnabled: true, soundVolume: 50,
  calendar: true, meetingNudges: false, meetingNudgeEvery: 25,
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

function decide() {}
function postpone() {}
function skip() {}
function nudgeDue() {}
function micBusy() {}
function excluded() {}
function parseProbe() {}
var EXERCISES = []
var NUDGES = []
var TIPS = []
function pickBreak() {}
function reps() {}
function streak() {}
function dayKey() {}
function parseHistory() {}
function todayStats() {}

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
  var p = bodyIn - (mid - st.eyes) <= c.merge
    ? { kind: "body", in: Math.min(bodyIn, c.eyesMax - st.eyes) }
    : { kind: "eyes", in: mid - st.eyes }
  var len = p.kind === "body" ? c.bodyBreak : c.eyesBreak
  // ponytail: only the next meeting is checked; two back-to-back meetings push the break past the first one only
  var next = nextEvent(events, now)
  if (next) {
    var start = (next.start - now) / 1000, end = (next.end - now) / 1000
    var before = start - len - c.lead
    if (p.in > before && p.in < end) {
      var earliest = p.kind === "body" ? c.body - c.merge - st.body : c.eyesMin - st.eyes
      p.in = before >= earliest ? before : end + c.after
    }
  }
  if (st.snoozeUntil > now) p.in = Math.max(p.in, (st.snoozeUntil - now) / 1000)
  p.in = Math.max(0, p.in)
  return p
}
