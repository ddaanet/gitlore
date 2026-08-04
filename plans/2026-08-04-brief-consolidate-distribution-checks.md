## Brief: consolidate the distribution checks behind their own gate

2026-08-04

### Problem

`precommit_inputs` in `justfile` deliberately excludes `agents`, `commands` and
`skills` — the three directories the plugin actually distributes. `prerelease`
is `precommit`, so nothing on the release path re-checks the shipped surface
when only those directories changed: the sentinel hash does not move, the gate
prints `precommit: cached`, and the suites that assert on that surface never
run. The justfile documents the exclusion as a deliberate trade whose cover is
`just evals` — but evals is paid and explicitly off the release path, so in
practice the cover does not exist.

Confirmed live at the v0.4.5 release: `commands/add-tier.md`,
`skills/merge/SKILL.md` and `skills/push/SKILL.md` all changed since v0.4.4
with the gate reporting cached.

### Decisions

- Move the two stray structural tests into `tests/plugin_distribution.bats`,
  which is where they belong topically — it is the suite for "this repo as a
  distributed plugin":
  - `tests/cc_hook_recall.bats` — "the skill is discoverable with a description
    that names the mid-task trigger" (asserts `skills/recall/SKILL.md` head
    carries `name: recall` and `tool result`).
  - `tests/cc_hook_add_tier.bats` — "add-tier hook: the command file is flat
    under `commands/`" (asserts `commands/add-tier.md` exists and
    `commands/gitlore/` does not).
  Carry each test's regression comment across verbatim; they document incidents
  that actually happened, not rationale someone can re-derive.
- Give the distribution suite its own gate with its own sentinel, keyed on
  `agents commands skills` plus the suite file and its helpers. Wire it into
  `precommit` (and so into `prerelease`) as a dependency.

### Constraints

- `check-sentinel` sets the shell variables `sentinel` and `gate_inputs`, and
  `record-sentinel` reads them back. Two gates cannot share one shebang recipe
  body — the second `check-sentinel` clobbers the first's state. The new gate
  must be its own recipe.
- `tests/justfile_gates.bats` guards the inputs declaration in both directions:
  every declared path must exist, and every top-level entry must be either
  declared or named in that suite's exclusion list. A new inputs variable has to
  keep it green, and `agents`/`commands`/`skills` moving from "excluded" to
  "declared" is exactly what that suite is watching.
- Both suites already `load helpers/setup` and reference `$PLUGIN_ROOT`, so the
  moved tests should need no rewriting — verify rather than assume.
- Whichever way it is wired, `evals_inputs` is currently `precommit_inputs`
  plus the three directories; that composition needs re-checking so evals does
  not lose or double-count coverage.

### Rejected approaches

- **Widen `precommit_inputs` to include the three directories.** Correct on
  coverage, wrong on cost: every prose edit to a skill body would re-run the
  entire bats suite to reach assertions that take 1.8s. Measured — the full
  `plugin_distribution.bats` is 10 tests in 1.8s, pure file reads and frontmatter
  greps, no fixture repos.
- **Rely on `GITLORE_GATE_FORCE=1` before a release.** Manual, undocumented as a
  release step, and depends on someone remembering the blind spot exists.
- **Rely on `just evals`.** Its input set does cover the three directories, but
  it drives the real claude CLI, costs time and money, and is deliberately not a
  release dependency.

### Additional context

The checks guard the *invocation path*, not content — that Claude Code can
discover and dispatch what ships. They are cheap and individually unlikely to
break, but each one exists because it broke once: `Agent type not found` from a
missing `name:` in agent frontmatter, `/gitlore:gitlore:install` from a
`commands/gitlore/` subdir, a `100644` script that fails the skill's one Bash
call for every installed user. Low frequency, high blast radius, near-zero cost
once wired correctly — which is the case for a gate, not against one.

This brief's recommendation is input, not a decision. Surface the wiring choice
before implementing.
