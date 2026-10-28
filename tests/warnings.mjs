// Prints what the menu lacks as warnings on the run's page: the window
// controls kyrr's contract calls a `gap`, and the acknowledged mismatches in
// known-gaps.json. They do not fail anything.
import { loadContract, knownGaps } from "./helpers.mjs"

const contract = await loadContract()
const warnings = []
for (const [control, entry] of Object.entries(contract.parity))
  if (entry.gap) warnings.push(`window control "${control}" is a gap in the menu: ${entry.gap}`)
for (const gap of knownGaps())
  warnings.push(`window control "${gap.control}" (${gap.command}) is not sent by the menu: ${gap.why}`)

for (const warning of warnings) console.log(`::warning title=kyrr contract::${warning}`)
if (process.env.GITHUB_STEP_SUMMARY && warnings.length) {
  const { appendFileSync } = await import("node:fs")
  appendFileSync(process.env.GITHUB_STEP_SUMMARY, `### Window controls without a counterpart in the menu\n\n${warnings.map((w) => `- ${w}`).join("\n")}\n`)
}
