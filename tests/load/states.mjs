// Writes the states the load job shows, one JSON file each, and plan.tsv: for
// each file the pages to look at. Usage: node states.mjs <folder>
import { mkdirSync, writeFileSync } from "node:fs"
import path from "node:path"
import { loadContract } from "../helpers.mjs"
import { variants } from "../variants.mjs"

const folder = process.argv[2]
mkdirSync(folder, { recursive: true })
const contract = await loadContract()

const all = ["main", "filter", "voice", "dictation", "memos", "recordings", "setup", "mic", "about", "updateNews", "ai", "asr", "text"]
// variant name → the pages to look at ("text": the first recording's)
const plan = {
  "sample as it is": all,
  "English": all,
  "setup step 1": ["main"],
  "setup step 2": ["main"],
  "setup step 3": ["main"],
  "filter detached, moveTo set": ["main", "filter"],
  "dictation key unbound with a button": ["main", "dictation"],
  "dictation, model downloading": ["main", "dictation"],
  "memos empty list": ["main", "memos", "recordings"],
  "many memos": ["recordings"],
  "memo rework original": ["text"],
  "memo not ready, cannot write": ["text"],
  "ai missing (kyrr 0.7)": ["main", "setup"],
  "asr on, found, with models": ["main", "ai", "asr", "setup"],
  "update available, installable": ["main", "setup", "updateNews"],
  "update available, not installable": ["main", "setup"],
  "update download failed": ["main"],
  "overload note switched": ["main"],
  "alert 4": ["main"]
}

const lines = []
let n = 0
for (const { name, state } of variants(contract.state)) {
  if (!plan[name]) continue
  n++
  // Every state has a number of its own as its pid, so the test can tell
  // when the menu has read the one it just wrote.
  state.pid = 1000 + n
  const file = `${String(n).padStart(2, "0")}.json`
  writeFileSync(path.join(folder, file), JSON.stringify(state))
  const text = state.memos && state.memos.list && state.memos.list[0] ? state.memos.list[0].id : ""
  const pages = state.setupDone === false ? ["main"] : plan[name]
  lines.push([file, state.pid, name.replace(/[\t,]/g, " "), pages.map((p) => (p === "text" ? (text ? `text:${text}` : null) : p)).filter(Boolean).join(",")].join("\t"))
}
const missing = Object.keys(plan).filter((name) => !variants(contract.state).some((v) => v.name === name))
if (missing.length) throw new Error(`variants not in variants.mjs: ${missing.join(", ")}`)
writeFileSync(path.join(folder, "plan.tsv"), lines.join("\n") + "\n")
