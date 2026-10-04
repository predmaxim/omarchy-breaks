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

function newState() {}
function tick() {}
function credit() {}
function plan() {}
function decide() {}
function busyEvents() {}
function eventAt() {}
function nextEvent() {}
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
