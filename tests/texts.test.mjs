// Texts.js: German and English say the same things.
import test from "node:test"
import assert from "node:assert/strict"
import { loadScript, source } from "./helpers.mjs"

const Texts = loadScript("Texts.js")
const de = Object.keys(Texts.de)
const en = Object.keys(Texts.en)
const holes = (text) => (String(text).match(/\{\}/g) || []).length

test("texts: German and English have the same keys", () => {
  assert.deepEqual(de.filter((key) => !(key in Texts.en)).map((key) => `${key}: missing in en`), [])
  assert.deepEqual(en.filter((key) => !(key in Texts.de)).map((key) => `${key}: missing in de`), [])
})

test("texts: every key has the same {} in both, and text() fills one at most", () => {
  const problems = []
  for (const key of de) {
    if (!(key in Texts.en)) continue
    if (holes(Texts.de[key]) !== holes(Texts.en[key]))
      problems.push(`${key}: ${holes(Texts.de[key])} {} in de, ${holes(Texts.en[key])} in en`)
    if (holes(Texts.de[key]) > 1 || holes(Texts.en[key]) > 1) problems.push(`${key}: more than one {}, text() fills the first only`)
  }
  assert.deepEqual(problems, [])
})

test("texts: no text is empty or a string that is no text", () => {
  const problems = []
  for (const [lang, table] of [["de", Texts.de], ["en", Texts.en]])
    for (const [key, value] of Object.entries(table))
      if (typeof value !== "string" || value.trim() === "") problems.push(`${lang}.${key} is empty`)
  assert.deepEqual(problems, [])
})

test("texts: every key written out in Panel.qml and Views.js exists in both languages", () => {
  const problems = []
  for (const file of ["Panel.qml", "Views.js"]) {
    const code = source(file)
    for (const match of code.matchAll(/\bt\("(\w+)"/g)) {
      const line = code.slice(0, match.index).split("\n").length
      for (const lang of ["de", "en"])
        if (!(match[1] in Texts[lang])) problems.push(`${file}:${line}: t("${match[1]}") is missing in ${lang}`)
    }
  }
  assert.deepEqual(problems, [])
})
