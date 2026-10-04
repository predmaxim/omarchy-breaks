// node test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")
const L = new Function(fs.readFileSync(path.join(__dirname, "logic.js"), "utf8").replace(".pragma library", "") +
  "; return { DEFAULTS, normalize, seconds, readEntry, newState, tick, credit, plan, decide, busyEvents, eventAt, nextEvent," +
  " postpone, skip, nudgeDue, NUDGES, TIPS, micBusy, excluded, parseProbe, EXERCISES, pickBreak, reps, streak, dayKey, parseHistory, todayStats }")()

// Settings: defaults fill gaps, junk falls back, numbers are clamped, eyesMax >= eyesMin.
assert.deepStrictEqual(L.normalize({}), L.DEFAULTS)
assert.deepStrictEqual(L.normalize(undefined), L.DEFAULTS)
assert.strictEqual(L.normalize({ eyesMin: "abc" }).eyesMin, 30)
assert.strictEqual(L.normalize({ bodyEvery: 9999 }).bodyEvery, 240)
assert.strictEqual(L.normalize({ eyesMin: 40, eyesMax: 20 }).eyesMax, 40)
assert.strictEqual(L.normalize({ strictness: "brutal" }).strictness, "hard")
assert.strictEqual(L.normalize({ strictness: "soft" }).strictness, "soft")
assert.strictEqual(L.normalize({ debug: "yes" }).debug, false)
assert.strictEqual(L.normalize({ junk: 1 }).junk, undefined)

// Seconds: minutes become seconds, debug turns minutes into seconds.
let c = L.seconds(L.DEFAULTS)
assert.strictEqual(c.body, 3600); assert.strictEqual(c.eyesMin, 1800); assert.strictEqual(c.eyesMax, 3000)
assert.strictEqual(c.eyesBreak, 90); assert.strictEqual(c.micro, 1200); assert.strictEqual(c.merge, 900)
assert.strictEqual(L.seconds(L.normalize({ debug: true })).body, 60)
assert.strictEqual(L.seconds(L.normalize({ microEnabled: false })).micro, 0)
assert.strictEqual(L.seconds(L.normalize({ meetingNudges: true })).nudge, 1500)
assert.strictEqual(c.nudge, 0)

// shell.json: the entry is the bar widget's, in any section; no entry -> {}, broken JSON -> null.
const cfg = { bar: { layout: { left: [], right: [{ id: "x" }, { id: "predmaxim.breaks", eyesMin: 25 }] } } }
assert.deepStrictEqual(L.readEntry(JSON.stringify(cfg), "predmaxim.breaks"), { id: "predmaxim.breaks", eyesMin: 25 })
assert.deepStrictEqual(L.readEntry("{}", "predmaxim.breaks"), {})
assert.strictEqual(L.readEntry("{oops", "predmaxim.breaks"), null)

console.log("settings ok")

// --- counters
c = L.seconds(L.DEFAULTS)
let st = L.newState()
st = L.tick(st, 10, 0, c)
assert.deepStrictEqual([st.eyes, st.body, st.micro], [10, 10, 10])
// Idle: nothing counts; a long enough absence is a break.
st = { eyes: 1000, body: 2000, micro: 900, snoozeUntil: 0, postponed: 0 }
assert.deepStrictEqual(L.tick(st, 1, 10, c), st)
assert.deepStrictEqual([L.tick(st, 1, 25, c).micro], [0])                       // >= microSeconds
assert.deepStrictEqual(Object.values(L.tick(st, 1, 90, c)).slice(0, 3), [0, 2000, 0])  // >= eyesBreakSeconds
assert.deepStrictEqual(Object.values(L.tick(st, 1, 420, c)).slice(0, 3), [0, 0, 0])    // >= bodySeconds
// Credit: body clears everything, eyes keeps body.
assert.deepStrictEqual(L.credit({ eyes: 5, body: 5, micro: 5, snoozeUntil: 9, postponed: 2 }, "body"),
  { eyes: 0, body: 0, micro: 0, snoozeUntil: 0, postponed: 0 })
assert.deepStrictEqual(L.credit({ eyes: 5, body: 5, micro: 5, snoozeUntil: 9, postponed: 2 }, "eyes"),
  { eyes: 0, body: 5, micro: 0, snoozeUntil: 0, postponed: 0 })
assert.deepStrictEqual(L.credit({ eyes: 5, body: 5, micro: 5, snoozeUntil: 9, postponed: 2 }, "micro"),
  { eyes: 5, body: 5, micro: 0, snoozeUntil: 9, postponed: 2 })

// --- plan: a normal hour is eyes at 40, body at 60
const M = 60, now = Date.UTC(2026, 9, 5, 9, 0)
const S = (eyes, body, extra) => Object.assign({ eyes: eyes * M, body: body * M, micro: 0, snoozeUntil: 0, postponed: 0 }, extra)
assert.deepStrictEqual(L.plan(S(0, 0), c, now, null), { kind: "eyes", in: 40 * M })
assert.deepStrictEqual(L.plan(S(0, 40), c, now, null), { kind: "body", in: 20 * M })
// Body close to the eye target: merged; body pulled to the eye deadline when it would come later.
assert.deepStrictEqual(L.plan(S(30, 50), c, now, null), { kind: "body", in: 10 * M })
assert.deepStrictEqual(L.plan(S(40, 45), c, now, null), { kind: "body", in: 10 * M })   // eye deadline 50 < body 60
// Overdue: in is never negative.
assert.deepStrictEqual(L.plan(S(10, 70), c, now, null), { kind: "body", in: 0 })
// Snooze pushes the break.
assert.deepStrictEqual(L.plan(S(40, 0, { snoozeUntil: now + 300000 }), c, now, null), { kind: "eyes", in: 300 })

// --- calendar
const ev = (fromMin, toMin) => ({ start: now + fromMin * 60000, end: now + toMin * 60000, title: "m" })
// Eyes due in 10 min, meeting in 5 for an hour, window open (eyes 30 >= 30): before it.
assert.deepStrictEqual(L.plan(S(30, 0), c, now, [ev(5, 65)]), { kind: "eyes", in: 5 * M - 90 - 60 })
// Window not open yet (eyes 20): after it, plus 2 min.
assert.deepStrictEqual(L.plan(S(20, 0), c, now, [ev(5, 65)]), { kind: "eyes", in: 65 * M + 120 })
// The meeting ends before the break: nothing moves.
assert.deepStrictEqual(L.plan(S(0, 0), c, now, [ev(5, 15)]), { kind: "eyes", in: 40 * M })
// Short meeting right at the break (Review Focus 4): the break goes before it, never onto its start.
let p = L.plan(S(35, 0), c, now, [ev(4, 6)])
assert.ok(p.in * 1000 + 90000 <= 4 * 60000, "break ends before the meeting")

// Events from the Datebook cache (Review Focus 2).
const cache = JSON.stringify({ events: [
  { title: "a", allDay: false, start: "2026-10-05T10:00:00Z", end: "2026-10-05T11:00:00Z", status: "confirmed", response: "accepted" },
  { title: "day", allDay: true, start: "2026-10-05T00:00:00Z", end: "2026-10-06T00:00:00Z" },
  { title: "x", allDay: false, start: "2026-10-05T12:00:00Z", end: "2026-10-05T13:00:00Z", status: "cancelled" },
  { title: "no", allDay: false, start: "2026-10-05T14:00:00Z", end: "2026-10-05T15:00:00Z", response: "declined" },
  { title: "b", allDay: false, start: "2026-10-05T08:00:00Z", end: "2026-10-05T08:30:00Z" },
  { title: "bad", allDay: false, start: "nope", end: "2026-10-05T08:30:00Z" }
] })
const evs = L.busyEvents(cache)
assert.deepStrictEqual(evs.map(e => e.title), ["b", "a"])
assert.strictEqual(L.busyEvents("{broken"), null)
assert.deepStrictEqual(L.busyEvents("{}"), [])
assert.strictEqual(L.eventAt(evs, Date.parse("2026-10-05T10:30:00Z")).title, "a")
assert.strictEqual(L.eventAt(evs, Date.parse("2026-10-05T11:00:00Z")), null)
assert.strictEqual(L.nextEvent(evs, Date.parse("2026-10-05T09:00:00Z")).title, "a")
assert.strictEqual(L.nextEvent(evs, Date.parse("2026-10-05T11:00:00Z")), null)

console.log("schedule ok")
