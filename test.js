// node test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")
const L = new Function(fs.readFileSync(path.join(__dirname, "logic.js"), "utf8").replace(".pragma library", "") +
  "; return { DEFAULTS, normalize, seconds, readEntry, newState, tick, credit, plan, decide, busyEvents, eventAt, nextEvent," +
  " postpone, skip, nudgeDue, NUDGES, TIPS, micBusy, excluded, parseProbe, EXERCISES, pickBreak, reps, streak, dayKey, parseHistory, todayStats, LIMITS, rowsFor, adjust }")()

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

assert.strictEqual(L.normalize({}).enabled, true)
assert.strictEqual(L.normalize({ enabled: false }).enabled, false)

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

// Overdue and a meeting too close to fit the break: after the meeting, never onto its start.
const evS = (fromSec, toMin) => ({ start: now + fromSec * 1000, end: now + toMin * 60000, title: "m" })
assert.deepStrictEqual(L.plan(S(90, 90), c, now, [evS(100, 30)]), { kind: "body", in: 30 * M + 120 })
assert.deepStrictEqual(L.plan(S(10, 70), c, now, [evS(200, 30)]), { kind: "body", in: 30 * M + 120 })

console.log("schedule ok")

// --- decide
const ctx = (o) => Object.assign({ events: null, busy: false, freeFor: 999, afterEvent: false }, o)
assert.strictEqual(L.decide(S(0, 0), c, now, ctx()).action, "none")
assert.strictEqual(L.decide(S(39.5, 0), c, now, ctx()).action, "warn")
assert.strictEqual(L.decide(S(40, 0), c, now, ctx()).action, "break")
assert.strictEqual(L.decide(S(40, 0), c, now, ctx({ busy: true })).action, "wait")
assert.strictEqual(L.decide(S(40, 0), c, now, ctx({ freeFor: 10 })).action, "wait")          // 30 s grace
assert.strictEqual(L.decide(S(40, 0), c, now, ctx({ freeFor: 60, afterEvent: true })).action, "wait")  // 120 s after a meeting
assert.strictEqual(L.decide(S(40, 0), c, now, ctx({ events: [ev(-5, 30)] })).action, "wait")
// Micro: due at 20 min, never within 5 min of a break, never while busy.
assert.strictEqual(L.decide(S(20, 20, { micro: 20 * M }), c, now, ctx()).action, "micro")
assert.strictEqual(L.decide(S(36, 36, { micro: 20 * M }), c, now, ctx()).action, "none")
assert.strictEqual(L.decide(S(20, 20, { micro: 20 * M }), c, now, ctx({ busy: true })).action, "none")
assert.strictEqual(L.decide(S(20, 20, { micro: 20 * M }), L.seconds(L.normalize({ microEnabled: false })), now, ctx()).action, "none")

// --- postpone and skip (Review Focus 5)
const hard = L.normalize({}), soft = L.normalize({ strictness: "soft" })
let s1 = L.postpone(S(40, 0), c, hard, now)
assert.deepStrictEqual([s1.postponed, s1.snoozeUntil], [1, now + 300000])
let s2 = L.postpone(s1, c, hard, now)
assert.strictEqual(s2.postponed, 2)
assert.strictEqual(L.postpone(s2, c, hard, now), null)
assert.strictEqual(L.skip(S(40, 0), "eyes", hard), null)
assert.strictEqual(L.skip(S(40, 0), "eyes", soft).eyes, 0)

// --- meeting nudges
const cn = L.seconds(L.normalize({ meetingNudges: true }))
assert.strictEqual(L.nudgeDue(ev(-24, 30), now, 0, cn), false)
assert.strictEqual(L.nudgeDue(ev(-25, 30), now, 0, cn), true)
assert.strictEqual(L.nudgeDue(ev(-50, 30), now, now - 10 * 60000, cn), false)
assert.strictEqual(L.nudgeDue(ev(-50, 30), now, 0, c), false)        // off by default
assert.strictEqual(L.nudgeDue(null, now, 0, cn), false)
assert.ok(L.NUDGES.length >= 4 && L.TIPS.length >= 3)

// --- sensors
assert.strictEqual(L.micBusy([{ isStream: true, isSink: false, audio: { muted: false } }]), true)
assert.strictEqual(L.micBusy([{ isStream: true, isSink: true, audio: { muted: false } }]), false)
assert.strictEqual(L.micBusy([{ isStream: true, isSink: false, audio: { muted: true } }]), false)
assert.strictEqual(L.micBusy([null, { isStream: false, isSink: false }]), false)
assert.strictEqual(L.excluded("Zoom", "zoom, teams"), true)
assert.strictEqual(L.excluded("firefox", "zoom,teams"), false)
assert.strictEqual(L.excluded("", ""), false)
assert.deepStrictEqual(L.parseProbe('{"class":"mpv","fullscreen":2}\n@@\ncam\n'), { fullscreen: true, cls: "mpv", camera: true })
assert.deepStrictEqual(L.parseProbe('{"class":"kitty","fullscreen":1}\n@@\n'), { fullscreen: false, cls: "kitty", camera: false })
assert.deepStrictEqual(L.parseProbe('{}\n@@\n'), { fullscreen: false, cls: "", camera: false })
assert.deepStrictEqual(L.parseProbe("garbage"), { fullscreen: false, cls: "", camera: false })

// --- exercises
const zero = () => 0
let eyes = L.pickBreak("eyes", c, [], 0, zero)
assert.strictEqual(eyes.length, 2)                                     // 90 s -> two
assert.ok(eyes.every(s => s.category === "eyes"))
assert.notStrictEqual(eyes[0].id, eyes[1].id)
assert.ok(!L.pickBreak("eyes", c, [eyes[0].id], 0, zero).some(s => s.id === eyes[0].id))   // no repeat of last time
assert.strictEqual(L.pickBreak("eyes", L.seconds(L.normalize({ eyesBreakSeconds: 45 })), [], 0, zero).length, 1)
let body = L.pickBreak("body", c, [], 0, zero)
assert.deepStrictEqual(body.map(s => s.category), ["body", "body", "eyes"])
assert.deepStrictEqual(L.pickBreak("body", c, [], 1, zero).map(s => s.category), ["body", "breath", "eyes"])
assert.ok(body.every(s => s.file && s.seconds > 0))
assert.strictEqual(L.reps(15, 0), 15); assert.strictEqual(L.reps(15, 7), 17); assert.strictEqual(L.reps(10, 99), 20)

// --- history and streak
const day = (d, h) => new Date(2026, 9, d, h || 12).getTime()
const hist = L.parseHistory([
  JSON.stringify({ ts: day(2), kind: "body", completed: true, exercises: [{ id: "squats", reps: 15 }] }),
  "not json",
  JSON.stringify({ ts: day(3), kind: "eyes", completed: true, exercises: [] }),
  JSON.stringify({ ts: day(4), kind: "body", completed: true, exercises: [{ id: "squats", reps: 16 }, { id: "calves", reps: 25 }] }),
  JSON.stringify({ ts: day(4, 15), kind: "body", completed: true, exercises: [{ id: "squats", reps: 16 }] }),
  ""
].join("\n"))
assert.strictEqual(hist.length, 4)
assert.strictEqual(L.streak(hist, day(4, 18)), 3)
assert.strictEqual(L.streak(hist, day(5, 9)), 3)                       // today not done yet: no break in the streak
assert.strictEqual(L.streak(hist, day(6, 9)), 0)
assert.strictEqual(L.streak(hist.concat([{ ts: day(4, 16), kind: "eyes", skipped: true }]), day(4, 18)), 0)
assert.deepStrictEqual(L.todayStats(hist, day(4, 18)), { breaks: 2, reps: { squats: 32, calves: 25 } })
assert.strictEqual(L.dayKey(day(4)), "2026-10-04")

console.log("decide ok")

// --- panel rows (keyboard)
const D = L.normalize({})
const ids = (tab, st) => L.rowsFor(tab, st).map(r => r.key || r.type)
assert.deepStrictEqual(ids("main", D), ["head", "breakNow", "soundEnabled", "calendar", "meetingNudges", "microEnabled", "strictness"])
assert.deepStrictEqual(ids("main", L.normalize({ strictness: "soft" })).slice(0, 3), ["head", "breakNow", "pause"])
assert.deepStrictEqual(ids("settings", D), ["head", "eyesMin", "eyesMax", "bodyEvery", "microEvery", "postponeCount", "soundVolume", "showMinutes", "debug"])
assert.deepStrictEqual(ids("settings", L.normalize({ microEnabled: false, soundEnabled: false })), ["head", "eyesMin", "eyesMax", "bodyEvery", "postponeCount", "showMinutes", "debug"])
const row = (tab, key) => L.rowsFor(tab, D).filter(r => r.key === key)[0]
assert.deepStrictEqual(L.adjust(row("settings", "eyesMin"), D, 1), { key: "eyesMin", value: 35 })
assert.deepStrictEqual(L.adjust(row("settings", "eyesMin"), D, -1), { key: "eyesMin", value: 25 })
assert.deepStrictEqual(L.adjust(row("settings", "eyesMin"), L.normalize({ eyesMin: 5 }), -1), null)   // at the limit
assert.deepStrictEqual(L.adjust(row("main", "microEnabled"), D, 1), { key: "microEnabled", value: false })
assert.deepStrictEqual(L.adjust(row("main", "strictness"), D, 1), { key: "strictness", value: "medium" })
assert.deepStrictEqual(L.adjust(row("main", "strictness"), D, -1), { key: "strictness", value: "soft" })
assert.deepStrictEqual(L.adjust(row("settings", "soundVolume"), D, 1), { key: "soundVolume", value: 60 })
assert.strictEqual(L.adjust({ type: "action", key: "breakNow" }, D, 1), null)

console.log("rows ok")
