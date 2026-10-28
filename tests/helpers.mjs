// Shared by the node tests: the plugin's JS files loaded as Quickshell loads
// them, kyrr's contract, and the matching of commands against it.
import { readFileSync } from "node:fs"
import vm from "node:vm"
import { fileURLToPath } from "node:url"
import path from "node:path"

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")

export function source(name) {
  return readFileSync(path.join(root, name), "utf8")
}

// A `.pragma library` file is one script with its own globals; the pragma is
// QML's, not JavaScript's.
export function loadScript(name) {
  const context = vm.createContext({})
  vm.runInContext(source(name).replace(/^\.pragma library.*$/m, ""), context, { filename: name })
  return context
}

// kyrr's contract (packaging/omarchy/contract.json in heast13/kyrr) at the ref
// in KYRR_REF, `main` unless said otherwise. KYRR_CONTRACT names a local copy
// instead, for working offline.
export async function loadContract() {
  if (process.env.KYRR_CONTRACT) return JSON.parse(readFileSync(process.env.KYRR_CONTRACT, "utf8"))
  const ref = process.env.KYRR_REF || "main"
  const url = `https://raw.githubusercontent.com/heast13/kyrr/${ref}/packaging/omarchy/contract.json`
  let last
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      const response = await fetch(url)
      if (response.ok) return await response.json()
      last = new Error(`${url}: HTTP ${response.status}`)
      // A ref or file that is not there will not appear by waiting.
      if (response.status === 404) break
    } catch (error) {
      last = error
    }
    await new Promise((resolve) => setTimeout(resolve, 1000 * 2 ** attempt))
  }
  throw new Error(`cannot read kyrr's contract (KYRR_REF=${ref}): ${last}`)
}

// Window controls the menu knowingly lacks a counterpart for, each with the
// reason: tests/known-gaps.json. Anything not in there fails the pages job.
export function knownGaps() {
  return JSON.parse(source("tests/known-gaps.json"))
}

// ---------------------------------------------------------------- commands

// The words of a line for kyrr's socket.
export function words(line) {
  return String(line).trim().split(/\s+/).filter(Boolean)
}

const isPlaceholder = (word) => /^<.*>$/.test(word)

// Whether the contract key (`mic <index>`, `set voice.tone`) is the start of
// `line`. `<x>` stands for any one word.
function startsWith(lineWords, keyWords) {
  if (keyWords.length > lineWords.length) return false
  return keyWords.every((word, i) => isPlaceholder(word) || word === lineWords[i])
}

// A key takes words after it when it is a `set` or its description opens with
// an argument: `<file name>: ...`, `[file name]: ...`, `0 none, 1 position, ...`.
function takesArguments(key, description) {
  return key.startsWith("set ") || /^[<\[\d]/.test(String(description))
}

// The contract key a line for the socket belongs to, or null.
export function matchCommand(commands, line) {
  const lineWords = words(line)
  let best = null
  for (const key of Object.keys(commands)) {
    const keyWords = words(key)
    if (!startsWith(lineWords, keyWords)) continue
    const extra = lineWords.length - keyWords.length
    if (extra > 0 && !takesArguments(key, commands[key])) continue
    if (!best || keyWords.length > words(best).length) best = key
  }
  return best
}

// ---------------------------------------------------------------- Panel.qml

// What Panel.qml sends to kyrr as a literal: the first string of each branch
// of every `send(...)`. The rest of such a line is a variable's value.
export function panelSends(qml) {
  const found = []
  const re = /(?<!function )\bsend\(/g
  let match
  while ((match = re.exec(qml))) {
    let i = re.lastIndex
    let depth = 1
    let branch = ""
    const branches = []
    while (i < qml.length && depth > 0) {
      const c = qml[i]
      if (c === '"' || c === "'") {
        let j = i + 1
        while (qml[j] !== c) j += qml[j] === "\\" ? 2 : 1
        branch += qml.slice(i, j + 1)
        i = j + 1
        continue
      }
      if (c === "(") depth++
      else if (c === ")") depth--
      if (depth === 0) break
      if (depth === 1 && (c === "?" || c === ":")) {
        branches.push(branch)
        branch = ""
      } else {
        branch += c
      }
      i++
    }
    branches.push(branch)
    // The branches after the first (the condition) of a ternary, or the one
    // argument of a plain call.
    const list = branches.length > 1 ? branches.slice(1) : branches
    for (const part of list) {
      const literal = part.trim().match(/^"((?:[^"\\]|\\.)*)"/)
      if (literal) found.push({ text: literal[1], dynamic: part.trim().length > literal[0].length })
    }
    const line = qml.slice(0, match.index).split("\n").length
    for (const entry of found) entry.line = entry.line || line
  }
  return found
}
