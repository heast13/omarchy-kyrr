// Reads what the load job collected and says whether the menu passed.
// Usage: node judge.mjs <folder>   (metrics.jsonl, qs.log, commands.log, run.log)
import { readFileSync, existsSync, appendFileSync, writeFileSync } from "node:fs"
import path from "node:path"
import { loadContract, matchCommand, root } from "../helpers.mjs"

const folder = process.argv[2]
const read = (name) => (existsSync(path.join(folder, name)) ? readFileSync(path.join(folder, name), "utf8") : "")
const records = read("metrics.jsonl").split("\n").filter(Boolean).map((line) => JSON.parse(line))
const failures = []
const fail = (message) => failures.push(message)

// A screen this high shows every page whole: the list must not scroll.
const FITS = 1080

const scrolling = []
for (const r of records) {
  const where = `${r.size} · ${r.variant} · ${r.page}`
  const m = r.metrics
  if (!m || !m.loaded) { fail(`${where}: the widget did not load`); continue }
  if (r.scenario === "not-installed") {
    if (m.running) fail(`${where}: running without kyrr`)
    if (!m.rowIds.includes("install")) fail(`${where}: no install row without kyrr (rows: ${m.rowIds})`)
    continue
  }
  if (!m.opened) fail(`${where}: the menu is not open`)
  if (!m.running) fail(`${where}: the menu does not see kyrr running`)
  if (m.page !== r.page) fail(`${where}: the menu is on page "${m.page}"`)
  if (!(m.rows > 0)) fail(`${where}: no rows`)
  if (m.pid !== r.pid) fail(`${where}: the menu shows another state than the one written (pid ${m.pid}, wanted ${r.pid})`)
  const p = m.panel
  if (!p || !p.visible || !(p.contentWidth > 0) || !(p.contentHeight > 0)) { fail(`${where}: the menu card did not appear`); continue }
  const [w, h] = r.size.split("x").map(Number)
  if (p.screenW !== w || p.screenH !== h) fail(`${where}: the screen is ${p.screenW}x${p.screenH}, not ${r.size}`)
  if (p.contentHeight > h || p.contentWidth > w) fail(`${where}: the card (${p.contentWidth}x${p.contentHeight}) is bigger than the screen`)
  if (p.x < 0 || p.y < 0 || p.x + p.contentWidth > w || p.y + p.contentHeight > h)
    fail(`${where}: the card at ${p.x},${p.y} (${p.contentWidth}x${p.contentHeight}) leaves the screen`)
  if (!m.list) fail(`${where}: the list of rows was not found`)
  else if (m.list.interactive) {
    if (h >= FITS) fail(`${where}: the page scrolls on a screen ${h} high (rows ${m.list.contentHeight} px, room ${Math.round(m.list.room)} px)`)
    else scrolling.push(`${r.size} · ${r.variant} · ${r.page}: ${m.list.contentHeight} px of rows in ${Math.round(m.list.room)} px`)
  }
}

// The log: a QML problem with the plugin's files or the Omarchy types it uses.
const PROBLEM = /is not a type|ReferenceError|TypeError|Cannot assign to non-existent property|Unable to assign|Binding loop|is not installed|is not defined|Cannot read property|Cannot call method|Cannot anchor|Plugin widget .* failed|Failed to load|unavailable|Could not load|File not found/
const MINE = /omarchy-kyrr|\/Panel\.qml|\/Texts\.js|\/Views\.js|\/Commons\/|\/Ui\/|qs\.Commons|qs\.Ui/
const log = read("qs.log").split("\n")
const seen = new Set()
for (const line of log) {
  if (PROBLEM.test(line) && MINE.test(line) && !seen.has(line)) {
    seen.add(line)
    fail(`quickshell log: ${line.trim()}`)
  }
}
if (/\bFATAL\b|Segmentation fault|core dumped|terminate called/.test(read("qs.log"))) fail("quickshell log: quickshell crashed")

// What the menu sent to the fake kyrr is in kyrr's contract.
const contract = await loadContract()
const sent = new Set()
for (const line of read("commands.log").split("\n")) {
  const command = line.trim()
  if (!command || command === "background" || sent.has(command)) continue
  sent.add(command)
  if (matchCommand(contract.commands, command) === null) fail(`kyrr's socket got "${command}", which is no command of the contract`)
}

// The install and update buttons run the script that is in the plugin's folder.
const unquote = (text) => text.replace(/^'/, "").replace(/'$/, "").replace(/'\\''/g, "'")
const ran = { install: 0, update: 0 }
for (const line of read("run.log").split("\n")) {
  const launch = line.match(/^omarchy-launch-floating-terminal-with-presentation (.*)$/)
  if (!launch) continue
  const script = unquote(launch[1]).match(/^bash '(.+)' (install|update)$/)
  if (!script) { fail(`run.log: unexpected install command: ${line}`); continue }
  ran[script[2]]++
  if (script[1] !== path.join(root, "update.sh")) fail(`run.log: the menu runs ${script[1]}, not this plugin's update.sh`)
  else if (!existsSync(script[1])) fail(`run.log: ${script[1]} does not exist`)
}
for (const mode of ["install", "update"])
  if (!ran[mode]) fail(`the menu never ran update.sh ${mode} (no row did it, or the command is not the expected one)`)

// A short summary for the run's page.
const lines = [`### Load test`, ``, `${records.length} pages measured, ${failures.length} problems.`]
if (scrolling.length) lines.push(``, `Pages that scroll on screens under ${FITS} px high (allowed):`, ...scrolling.slice(0, 40).map((s) => `- ${s}`))
if (failures.length) lines.push(``, `Problems:`, ...failures.slice(0, 60).map((s) => `- ${s}`))
const summary = lines.join("\n")
console.log(summary)
writeFileSync(path.join(folder, "summary.md"), summary + "\n")
if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary + "\n")
process.exit(failures.length ? 1 : 0)
