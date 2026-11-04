// A label that does not fit its row is cut off ("…") in the menu, and nobody
// sees it unless they look at that very row. Omarchy's menu width is not ours
// to measure, so this keeps every label of a row that shares its line with a
// control under a length that is known to fit (the longest labels shipped
// since 0.8.0, a little rounded up). Longer text belongs in an info row, which
// wraps. 0.8.2's word-order switch ("Ausbessern korrigiert auch die Satzstellung",
// 43 characters) went through the gate cut off; this fails for it.
import test from "node:test"
import assert from "node:assert/strict"
import { loadScript, loadContract } from "./helpers.mjs"
import { variants } from "./variants.mjs"

const contract = await loadContract()
const Views = loadScript("Views.js")
const Texts = loadScript("Texts.js")
const pageNames = ["main", ...[...Views.page_.toString().matchAll(/case "(\w+)":/g)].map((m) => m[1])]

// Characters a label of that kind may have in either language.
const MOST = { switch: 36, choice: 24, slider: 14, key: 12, action: 36, radio: 24 }

// Entries of a drop-down: the same row, so the same room.
const MOST_OPTION = 34

function tooLong(rows) {
  const labels = rows.filter((row) => MOST[row.kind] && typeof row.label === "string" && row.label.length > MOST[row.kind])
  const options = rows.flatMap((row) =>
    row.kind === "choice" && Array.isArray(row.options)
      ? row.options.filter((o) => typeof o.label === "string" && o.label.length > MOST_OPTION).map((o) => ({ kind: "option", label: o.label }))
      : [])
  return [...labels, ...options]
}

test("labels of rows with a control beside them stay short enough not to be cut off", () => {
  const long = new Set()
  for (const { state } of variants(contract.state)) {
    for (const german of [true, false]) {
      const t = (key, value) => Texts.text(german, key, value)
      for (const page of pageNames) {
        let view
        try {
          view = Views.build(page, JSON.parse(JSON.stringify(state)), t)
        } catch {
          continue
        }
        for (const row of tooLong(view.rows))
          long.add(`${german ? "de" : "en"} ${page} ${row.kind}: "${row.label}" is ${row.label.length} characters, the most is ${MOST[row.kind] || MOST_OPTION}`)
      }
    }
  }
  assert.deepEqual([...long], [])
})

test("a label above the budget is found (self-test)", () => {
  const rows = [{ kind: "switch", label: "Ausbessern korrigiert auch die Satzstellung" }, { kind: "switch", label: "Satzstellung korrigieren" }]
  assert.deepEqual(tooLong(rows).map((row) => row.label), ["Ausbessern korrigiert auch die Satzstellung"])
})
