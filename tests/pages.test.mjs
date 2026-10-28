// Every page of the menu, built from every state kyrr can plausibly be in, in
// both languages: nothing throws, every text exists, every row is one Panel.qml
// draws and does something kyrr understands.
import test from "node:test"
import assert from "node:assert/strict"
import { loadScript, loadContract, source, matchCommand, panelSends, words, knownGaps } from "./helpers.mjs"
import { variants } from "./variants.mjs"

const contract = await loadContract()
const Views = loadScript("Views.js")
const Texts = loadScript("Texts.js")
const panelQml = source("Panel.qml")

// ------------------------------------------------------- what Panel.qml has

// The rows Panel.qml draws: the Loader's chain picks a component for seven
// kinds, and the rest are the selectable ones its comment lists.
const drawn = new Set([...panelQml.matchAll(/row\.kind === "(\w+)"\s*\?/g)].map((m) => m[1]))
const selectableList = panelQml.match(/Every row the cursor can stop on: ([^.]*)\./)
const rowKinds = new Set([...drawn, ...(selectableList ? selectableList[1].replace(/\s*\/\/\s*/g, " ").split(/,\s*/) : [])])
// What a button of a row of buttons does without a `cmd`, by its id.
const buttonIds = new Set([...panelQml.matchAll(/\bb\.id === "(\w+)"/g)].map((m) => m[1]))
// The one action Panel.qml handles itself.
const ownActions = new Set([...panelQml.matchAll(/\brow\.id === "(\w+)"\) \{/g)].map((m) => m[1]))

// ------------------------------------------------------- what Views.js knows

// "main" is the default of the switch, the others are its cases.
const pageNames = ["main", ...[...Views.page_.toString().matchAll(/case "(\w+)":/g)].map((m) => m[1])]

const BAD_TEXT = /\bundefined\b|\bnull\b|\bNaN\b|\bInfinity\b|\[object|\{\}/
const KINDS_WITH_LABEL = new Set(["switch", "choice", "slider", "key", "action", "radio", "memo", "section", "progress"])
const NEEDS_CMD = new Set(["switch", "choice", "slider", "key", "radio"])

// ------------------------------------------------------- the check

const emitted = new Map() // normalised line for kyrr's socket → where

function normalise(line) {
  return String(line).replace(/\{\}/g, "x").trim()
}

function checkText(problems, where, what, value) {
  if (typeof value === "string" && BAD_TEXT.test(value)) problems.push(`${where}: ${what} is "${value}"`)
}

function checkCommand(problems, where, line, via) {
  const normalised = normalise(line)
  if (!emitted.has(normalised)) emitted.set(normalised, where)
  if (matchCommand(contract.commands, normalised) === null)
    problems.push(`${where}: ${via} "${line}" is no command of kyrr's contract`)
}

function checkView(view, k, page, t) {
  const problems = []
  const where = `${page}`
  const rows = view.rows
  if (typeof view.title !== "string") problems.push(`${where}: title is ${typeof view.title}`)
  checkText(problems, where, "title", view.title)
  if (!Array.isArray(rows)) return [`${where}: no rows`]
  const ids = new Set()
  rows.forEach((row, i) => {
    const at = `${where} row ${i} (${row.kind}${row.id ? " " + row.id : ""})`
    if (!rowKinds.has(row.kind)) problems.push(`${at}: Panel.qml does not draw a row of this kind`)
    if (row.id !== undefined) {
      if (ids.has(row.id)) problems.push(`${at}: id used twice on this page`)
      ids.add(row.id)
    }
    for (const field of ["label", "caption", "value", "placeholder", "unit"]) checkText(problems, at, field, row[field])
    if (KINDS_WITH_LABEL.has(row.kind) && (typeof row.label !== "string" || row.label === ""))
      problems.push(`${at}: no label`)
    if (row.kind === "info" && (typeof row.label !== "string" || (row.label === "" && !row.body)))
      problems.push(`${at}: no label`)
    for (const option of row.options || []) checkText(problems, at, "option", option.label)

    // Rows that do something.
    if (NEEDS_CMD.has(row.kind) && (typeof row.cmd !== "string" || row.cmd === "")) problems.push(`${at}: no cmd`)
    if (row.kind === "action" && row.cmd === undefined && !row.page && !ownActions.has(row.id))
      problems.push(`${at}: does nothing (no cmd, no page)`)
    if (row.kind === "memo" && (!row.page || !row.play)) problems.push(`${at}: no page or play`)
    if (row.kind === "edit" && !row.cmd && !row.rename) problems.push(`${at}: nothing to send`)
    if (row.kind === "edit" && row.secret && row.value !== "") problems.push(`${at}: a secret is filled in`)
    if (row.kind === "radio" && typeof row.checked !== "boolean") problems.push(`${at}: checked is ${typeof row.checked}`)
    if (row.kind === "choice") {
      if (!Array.isArray(row.options) || row.options.length < 1) problems.push(`${at}: no options`)
      else if (!row.options.some((o) => o.value === row.value))
        problems.push(`${at}: value ${JSON.stringify(row.value)} is none of its options`)
    }
    if (row.kind === "slider") {
      for (const field of ["value", "min", "max", "step"])
        if (typeof row[field] !== "number" || !Number.isFinite(row[field])) problems.push(`${at}: ${field} is not a number`)
      if (typeof row.unit !== "string") problems.push(`${at}: no unit`)
    }
    if (row.kind === "progress" && (typeof row.value !== "number" || !Number.isFinite(row.value)))
      problems.push(`${at}: value is not a number`)

    // What reaches kyrr.
    if (row.cmd) checkCommand(problems, at, row.cmd, "cmd")
    if (row.play) checkCommand(problems, at, row.play, "play")
    if (row.rename) emitted.set("memo rename x", at)
    for (const button of row.buttons || []) {
      const b = `${at} button ${button.id}`
      checkText(problems, b, "label", button.label)
      if (typeof button.label !== "string" || button.label === "") problems.push(`${b}: no label`)
      if (button.cmd) checkCommand(problems, b, button.cmd, "cmd")
      else if (!buttonIds.has(button.id)) problems.push(`${b}: does nothing (no cmd, Panel.qml does not know it)`)
    }

    // Where a row leads.
    if (row.page) {
      let target
      try {
        target = Views.build(row.page, k, t)
      } catch (e) {
        problems.push(`${at}: page "${row.page}" throws: ${e}`)
      }
      // A page that is not there falls back to the main page (no title) or
      // to "this recording is gone".
      if (target && (target.title === "" || (row.page.startsWith("text:") && target.rows.some((r) => r.label === t("memoGone")))))
        problems.push(`${at}: opens page "${row.page}", which Views.js does not build`)
      if (!row.page.startsWith("text:") && !pageNames.includes(row.page))
        problems.push(`${at}: opens page "${row.page}", which Views.js does not know`)
    }
  })
  return problems
}

const results = [] // { name, problems }
const textKeysUsed = new Set()

for (const { name, state } of variants(contract.state)) {
  const problems = []
  const memos = state.memos || {}
  const ids = new Set((memos.list || []).map((m) => m.id))
  if (memos.sheet) ids.add(memos.sheet.id)
  const pages = [...pageNames, ...[...ids].map((id) => `text:${id}`), "text:vanished", "nonsense"]
  for (const german of [true, false]) {
    const k = JSON.parse(JSON.stringify(state))
    k.lang = german ? "de" : "en"
    const used = new Set()
    const t = (key, value) => {
      used.add(key)
      return Texts.text(german, key, value)
    }
    for (const page of pages) {
      const label = `${german ? "de" : "en"} ${page}`
      let view
      try {
        view = Views.build(page, k, t)
      } catch (e) {
        problems.push(`${label}: Views.build throws: ${e.stack.split("\n")[0]}`)
        continue
      }
      problems.push(...checkView(view, k, label, t))
      // A page that needs the local AI is not one without it: Panel.qml
      // catches a throw as "kyrr is too old", so these must fall back.
      const needs = page === "ai" ? !(k.ai && k.ai.features && k.ai.asr) : page === "asr" ? !(k.ai && k.ai.asr) : false
      if (needs && JSON.stringify(view) !== JSON.stringify(Views.build("main", k, t)))
        problems.push(`${label}: reachable without the local AI`)
    }
    for (const key of used) {
      textKeysUsed.add(key)
      for (const [lang, table] of [["de", Texts.de], ["en", Texts.en]])
        if (!Object.prototype.hasOwnProperty.call(table, key)) problems.push(`${german ? "de" : "en"}: text "${key}" is missing in ${lang}`)
    }
  }
  results.push({ name, problems: [...new Set(problems)] })
}

for (const { name, problems } of results) {
  test(`pages: ${name}`, () => {
    assert.deepEqual(problems, [])
  })
}

test("pages: Views.js knows the pages the test expects", () => {
  for (const page of ["main", "filter", "voice", "dictation", "memos", "recordings", "setup", "mic", "about", "updateNews", "ai", "asr"])
    assert.ok(pageNames.includes(page), `page ${page} not found in Views.page_`)
  assert.ok(rowKinds.size >= 13, `row kinds read from Panel.qml: ${[...rowKinds]}`)
  assert.ok(buttonIds.has("deleteMemo") && buttonIds.has("copy"), `button ids read from Panel.qml: ${[...buttonIds]}`)
  assert.ok(ownActions.has("install"), "Panel.qml's own action not found")
})

// ------------------------------------------------------- Panel.qml's own lines

const panelProblems = []
const sends = panelSends(panelQml)
for (const { text, dynamic, line } of sends) {
  const command = dynamic ? `${text.trim()} x` : text.trim()
  emitted.set(command, `Panel.qml:${line}`)
  if (matchCommand(contract.commands, command) === null)
    panelProblems.push(`Panel.qml:${line}: send("${text}") is no command of kyrr's contract`)
}

test("Panel.qml: every line it sends is a command of kyrr's contract", () => {
  assert.ok(sends.length >= 15, `only ${sends.length} send() literals found in Panel.qml`)
  assert.deepEqual(panelProblems, [])
})

// ------------------------------------------------------- the contract's parity

const known = knownGaps()
const usedKnown = new Set()

test("contract: every window control with a plugin counterpart is sent by the menu", () => {
  const problems = []
  for (const [control, entry] of Object.entries(contract.parity)) {
    if (!entry.plugin) continue
    for (const command of entry.plugin) {
      const wanted = words(command)
      const sent = [...emitted.keys()].some((line) => {
        const have = words(line)
        return have.length >= wanted.length && wanted.every((w, i) => /^<.*>$/.test(w) || w === have[i])
      })
      if (sent) continue
      const acknowledged = known.find((gap) => gap.control === control && gap.command === command)
      if (acknowledged) usedKnown.add(acknowledged)
      else problems.push(`window control "${control}" has no counterpart in the menu: nothing sends "${command}"`)
    }
  }
  assert.deepEqual(problems, [])
})

test("contract: tests/known-gaps.json holds nothing that is not a gap any more", () => {
  const stale = known.filter((gap) => !usedKnown.has(gap)).map((gap) => `${gap.control} / ${gap.command}`)
  assert.deepEqual(stale, [])
})
