## Current task

The gitlore 0.4.0 release is deliberately gated behind making the `pass^5`
evals pass the `just prerelease` gate honestly. The code is release-ready; the
gate is red only on the two LLM-driven-half losses, not on store-side bugs. Next
session improves the evals, confirms a green gate, then releases. The full
account — root cause, judge fragility, what to try — is in
`memory/project_gitlore_global_memory.md` under the `pass^5` / NEXT entries.

## Open decisions

- **`04-tier-write` judge misfire (~1/5).** The commit message is correct but
  `judge.sh` parses the FIRST word of free-form model text, and the judge
  occasionally leads with the wrong token before self-correcting. Harden via a
  structured/enum verdict or a required `VERDICT: x` delimiter (fail-closed on
  absent), or accept it as safe-direction noise (it is fail-closed — it can only
  reject a good commit, never pass a bad one). Do NOT switch to a different
  positional scan; that only relocates the fragility.
- **`05-recall` loss (~1/5).** The agent sometimes answers without writing
  `.claude/gitlore-recall`. Tighten the scenario prompt, or accept the rate.
- **Do not ship over a red gate.** The `evals` sentinel records only a real
  green; hand-writing it to bypass `pass^5` is off the table.
- **Bump size** — `minor` (0.4.0), scope since v0.3.0 is D17 + D18 + index
  authority. Confirm before `just release`.
- **Authorization** — commit + `just release` (unsandboxed, clean tree, `main`)
  each need David's explicit go-ahead.
