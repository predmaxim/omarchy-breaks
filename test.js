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
