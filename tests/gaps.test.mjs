// The two things the menu once lacked against kyrr's window: reading and
// changing the wording of the language model's instructions, and the text of a
// recording beside the one before the rework.
import test from "node:test"
import assert from "node:assert/strict"
import { loadScript, loadContract, source } from "./helpers.mjs"

const contract = await loadContract()
const Views = loadScript("Views.js")
const Texts = loadScript("Texts.js")
const panelQml = source("Panel.qml")
const t = (key, value) => Texts.text(true, key, value)
const clone = (value) => JSON.parse(JSON.stringify(value))

function recording(change) {
  const k = clone(contract.state)
  change(k)
  const id = k.memos.sheet.id
  return Views.build(`text:${id}`, k, t).rows
}
const kinds = (rows) => [...rows.map((row) => row.kind)]
const byId = (rows, id) => rows.find((row) => row.id === id)

test("a recording with an original offers the text and the comparison", () => {
  const rows = recording((k) => { k.memos.sheet.rework.original = true; k.memos.sheet.view = 0 })
  const view = byId(rows, "view")
  assert.equal(view.cmd, "memo view {}")
  assert.equal(view.value, 0)
  assert.deepEqual([...view.options.map((o) => o.value)], [0, 1])
  assert.ok(kinds(rows).includes("editor") && !kinds(rows).includes("compare"))
})

test("the comparison replaces the text field, and the text tools with it", () => {
  const rows = recording((k) => { k.memos.sheet.rework.original = true; k.memos.sheet.view = 1 })
  assert.equal(byId(rows, "view").value, 1)
  assert.ok(kinds(rows).includes("compare") && !kinds(rows).includes("editor"))
  assert.equal(byId(rows, "textTools"), undefined)
  // The rework tools stay: the original back, apply again.
  assert.ok(byId(rows, "reworkTools").buttons.some((b) => b.id === "restore"))
})

test("while the language model works the text shows, not the comparison", () => {
  const rows = recording((k) => {
    k.memos.sheet.rework.original = true; k.memos.sheet.view = 1; k.memos.sheet.rework.busy = true
  })
  assert.ok(kinds(rows).includes("editor") && !kinds(rows).includes("compare"))
  assert.equal(byId(rows, "view"), undefined)
})

test("without an original there is no comparison to switch to", () => {
  const rows = recording((k) => { k.memos.sheet.rework.original = false; k.memos.sheet.view = 1 })
  assert.equal(byId(rows, "view"), undefined)
  assert.ok(kinds(rows).includes("editor"))
})

test("Local AI's page edits the instruction of each task", () => {
  for (const index of [0, 1, 2, 3]) {
    const k = clone(contract.state)
    k.ai.prompt = { index, own: index % 2 === 1, edit: true }
    const rows = Views.build("ai", k, t).rows
    const editor = byId(rows, "promptEditor")
    assert.equal(editor.kind, "editor")
    assert.equal(editor.channel, "prompt")
    assert.equal(editor.memo, String(index))
    const tools = byId(rows, "promptTools").buttons
    assert.deepEqual([...tools.map((b) => b.id)], ["promptSave", "promptReset"])
    assert.equal(tools[0].live, "promptDirty")
    assert.equal(tools[1].cmd, "set ai.promptReset")
  }
})

test("the menu hands the typed wording to kyrr the way the contract says", () => {
  assert.match(panelQml, /promptEditFile\.setText\(e\.memo \+ "\\n" \+ e\.text\)/)
  assert.match(panelQml, /root\.send\("set ai\.promptSave"\)/)
  assert.match(panelQml, /runtimeDir \+ "\/kyrr\/promptedit"/)
  assert.match(panelQml, /runtimeDir \+ "\/kyrr\/prompt"/)
  assert.match(panelQml, /runtimeDir \+ "\/kyrr\/compare"/)
  assert.ok(contract.commands["set ai.promptSave"] && contract.commands["memo view"])
})

// ---------------------------------------------------- a new plugin on its own

function mainRows(change, plugin) {
  const k = clone(contract.state)
  change(k)
  return Views.build("main", k, t, plugin).rows
}
const noUpdate = (k) => { k.update.state = "latest" }

test("versions are compared as dotted numbers", () => {
  assert.equal(Views.newer("1.10.0", "1.9.9"), true)
  assert.equal(Views.newer("1.3.0", "1.3"), false)
  assert.equal(Views.newer("1.3.1", "1.3"), true)
  assert.equal(Views.newer("1.2.0", "1.3.0"), false)
  assert.equal(Views.newer("2", "1.9"), true)
})

test("a newer plugin on GitHub gets its own row, with kyrr as it is", () => {
  const row = byId(mainRows(noUpdate, { version: "1.2.0", latest: "1.3.0" }), "installPlugin")
  assert.ok(row, "no row for the new plugin")
  assert.equal(row.kind, "action")
  assert.match(t("updatePluginHint", "1.3.0"), /1\.3\.0/)
})

test("no row while the plugin is current, unknown or not looked at", () => {
  for (const plugin of [undefined, { version: "1.3.0", latest: "1.3.0" }, { version: "1.3.0", latest: "" }, { version: "", latest: "1.3.0" }, { version: "1.5.0", latest: "1.3.0" }])
    assert.equal(byId(mainRows(noUpdate, plugin), "installPlugin"), undefined, JSON.stringify(plugin))
})

test("a new kyrr that updates the plugin with it hides the plugin-only row", () => {
  const rows = mainRows((k) => { k.update.state = "available"; k.update.installable = false; k.update.dismissed = false }, { version: "1.2.0", latest: "1.3.0" })
  assert.ok(byId(rows, "install"))
  assert.equal(byId(rows, "installPlugin"), undefined)
})

test("Panel.qml runs update.sh with the mode the row asks for", () => {
  assert.match(panelQml, /runUpdate\(row\.id === "installPlugin" \? "plugin" : root\.installed \? "update" : "install"\)/)
  assert.match(panelQml, /raw\.githubusercontent\.com\/heast13\/omarchy-kyrr\/main\/manifest\.json/)
  // The look at GitHub follows kyrr's own switch for automatic update checks.
  assert.match(panelQml, /!root\.kyrr\.general\.updateCheck/)
})

test("a kyrr that hands over neither the wording nor the comparison gets the old rows", () => {
  const k = clone(contract.state)
  k.ai.prompt = { index: 1, own: true }
  const rows = Views.build("ai", k, t).rows
  assert.equal(byId(rows, "promptEditor"), undefined)
  assert.equal(byId(rows, "promptTools"), undefined)
  assert.equal(byId(rows, "promptReset").cmd, "set ai.promptReset")
  const sheet = recording((k) => { k.memos.sheet.rework.original = true; delete k.memos.sheet.view })
  assert.equal(byId(sheet, "view"), undefined)
  assert.ok(kinds(sheet).includes("editor"))
})
