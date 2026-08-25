#!/usr/bin/env bats
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
# Planted file contents carry backticked spans and literal link syntax on
# purpose — they are fixtures for the checker to read, not expansions this
# suite wants.
# shellcheck disable=SC2016
#
# The checker reads `docs/` under the git toplevel, so every case plants a
# throwaway repo rather than asserting against this one. Three cases at the end
# run it against the real repo: the graph must be intact, the script must be
# executable, and `just precommit` must actually reach it.

load helpers/setup

CHECKER=

setup() {
  setup_tmp_repo
  CHECKER="$PLUGIN_ROOT/scripts/check-docs-links.py"
  mkdir -p docs/references
}
teardown() { teardown_tmp_repo; }

# The hub. Args are body lines appended after a fixed preamble.
plant_hub() {
  {
    printf '# gitlore Design Document\n\n'
    printf '## Design Decisions\n\n'
    printf '%s\n' "$@"
  } > docs/design.md
}

# A reference node. $1 = basename under docs/references/, rest are body lines.
plant_ref() {
  local name="$1"
  shift
  printf '%s\n' "$@" > "docs/references/$name"
}

# --- broken links ----------------------------------------------------------

@test "broken link: a pointer to a missing file blocks" {
  plant_hub 'Arguments in [the gate](references/commit-gate.md).'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken-link"* ]]
  [[ "$output" == *"references/commit-gate.md"* ]]
}

@test "broken link: a pointer that resolves is clean" {
  plant_ref "commit-gate.md" '# The commit gate'
  plant_hub 'Arguments in [the gate](references/commit-gate.md).'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "broken link: a target inside a code span is prose, not a pointer" {
  plant_hub 'A composed line reads `- [A](a.md) — hook` in the root index.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "broken link: an http target is not a path" {
  plant_hub 'See [the issue](https://github.com/anthropics/claude-code/issues/1).'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "broken link: a changelog entry is scanned too" {
  mkdir -p docs/changelog
  printf '# An entry\n\nSee [the design](../design.md) and [gone](gone.md).\n' \
    > docs/changelog/2026-01-01-a.md
  plant_hub 'Nothing here.'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gone.md"* ]]
}

# --- decisions: stubs and bodies -------------------------------------------

@test "unstubbed decision: a body with no conclusion line in the hub blocks" {
  plant_ref "commit-gate.md" '# The commit gate — decisions D9' '' \
    '**D9 — A sub-agent synthesizes the merge**' '' 'The argument.'
  plant_hub 'Arguments in [the gate](references/commit-gate.md).'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unstubbed-decision"* ]]
  [[ "$output" == *"D9"* ]]
}

@test "unstubbed decision: a body with a hub bullet is clean" {
  plant_ref "commit-gate.md" '# The commit gate — decisions D9' '' \
    '**D9 — A sub-agent synthesizes the merge**' '' 'The argument.'
  plant_hub 'Arguments in [the gate](references/commit-gate.md).' '' \
    '- **D9** — a sub-agent synthesizes the merge'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "unstubbed decision: a cluster sub-decision is concluded in its own node" {
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9, D10' '' \
    '- Composition — **D10** the tier manifest' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.'
  plant_hub 'See [tiers](references/tiered-memory.md).' '' '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "unstubbed decision: a wrapped summary bullet still concludes what its continuation lines name" {
  # `format-docs` hard-wraps a cluster summary, so a sub-decision's `**D10**`
  # can sit on an indented continuation line rather than the `- ` line itself.
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9, D10' '' \
    '- Composition — **D9** tiered memory, argued at length here ·' \
    '  **D10** the tier manifest' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.'
  plant_hub 'See [tiers](references/tiered-memory.md).' '' '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "unstubbed decision: a summary in some other node does not conclude it" {
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9, D10' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.'
  plant_ref "elsewhere.md" '# Elsewhere' '' '- Composition — **D10** the tier manifest'
  plant_hub 'See [tiers](references/tiered-memory.md) and [e](references/elsewhere.md).' \
    '' '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unstubbed-decision"* ]]
  [[ "$output" == *"D10"* ]]
}

@test "stub without body: a hub bullet whose argument lives nowhere blocks" {
  plant_hub '- **D9** — a sub-agent synthesizes the merge'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stub-without-body"* ]]
  [[ "$output" == *"D9"* ]]
}

@test "stub without body: a decision stated whole in the hub needs no node" {
  plant_hub '**D9 — A sub-agent synthesizes the merge**' '' \
    'Stated here in full, with its argument.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "duplicate decision: one number with a body in two nodes blocks" {
  plant_ref "a.md" '# A — decisions D9' '' '**D9 — First**' '' 'Argument.'
  plant_ref "b.md" '# B — decisions D9' '' '**D9 — Second**' '' 'Argument.'
  plant_hub 'See [a](references/a.md) and [b](references/b.md).' '' \
    '- **D9** — a sub-agent synthesizes the merge'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate-decision"* ]]
}

@test "duplicate conclusion: one number stubbed twice in the hub blocks" {
  plant_ref "a.md" '# A — decisions D9' '' '**D9 — First**' '' 'Argument.'
  plant_hub 'See [a](references/a.md).' '' \
    '- **D9** — a sub-agent synthesizes the merge' \
    '- **D9** — and again, from an earlier grouping'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate-conclusion"* ]]
}

@test "undefined decision: a citation with no decision behind it blocks" {
  plant_hub 'Both reduce to one shape (D77).'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"undefined-decision"* ]]
  [[ "$output" == *"D77"* ]]
}

@test "undefined decision: a citation inside a code span is not a citation" {
  plant_hub 'The fixture writes `D77` into the manifest.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

# --- decisions: a node's own enumeration -----------------------------------

@test "enumeration drift: a title claiming a decision the node lacks blocks" {
  plant_ref "a.md" '# A — decisions D9, D10' '' '**D9 — First**' '' 'Argument.'
  plant_hub 'See [a](references/a.md).' '' '- **D9** — first'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"enumeration-drift"* ]]
  [[ "$output" == *"D10"* ]]
}

@test "enumeration drift: a body the title omits blocks too" {
  plant_ref "a.md" '# A — decisions D9' '' '**D9 — First**' '' 'Argument.' '' \
    '**D10 — Second**' '' 'Argument.'
  plant_hub 'See [a](references/a.md).' '' '- **D9** — first' '- **D10** — second'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"enumeration-drift"* ]]
  [[ "$output" == *"D10"* ]]
}

@test "enumeration: a range spells out every number it covers" {
  plant_ref "a.md" '# A — decisions D9–D11' '' \
    '**D9 — First**' '' 'Argument.' '' \
    '**D10 — Second**' '' 'Argument.' '' \
    '**D11 — Third**' '' 'Argument.'
  plant_hub 'See [a](references/a.md).' '' \
    '- **D9** — first' '- **D10** — second' '- **D11** — third'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "enumeration: a node with no decisions in its heading is not enumerated" {
  plant_ref "a.md" '# Auto-memory retrieval' '' 'A method and its findings.'
  plant_hub 'See [a](references/a.md).'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

# --- orphans ---------------------------------------------------------------

@test "orphan: a node nothing points at warns without blocking" {
  plant_ref "a.md" '# A' '' 'A body.'
  plant_hub 'Nothing points at a.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphan-reference"* ]]
  [[ "$output" == *"a.md"* ]]
}

@test "orphan: a citation from outside docs counts as reachable" {
  plant_ref "a.md" '# A' '' 'A body.'
  plant_hub 'Nothing points at a.'
  mkdir -p memory/ddaanet
  printf 'Full evidence in `docs/references/a.md`.\n' > memory/ddaanet/f.md
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"orphan-reference"* ]]
}

# --- scope, suppression, reporting -----------------------------------------

@test "suppression: a hygiene-ok marker clears the line it sits on" {
  plant_hub 'A pointer to [nowhere](references/gone.md). <!-- hygiene-ok -->'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "whitespace: a docs path containing a space is scanned, not split" {
  plant_ref "a b.md" '# A B — decisions D9' '' '**D9 — First**' '' 'Argument.'
  plant_hub 'See [a b](<references/a b.md>).'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a b.md"* ]]
  [[ "$output" == *"unstubbed-decision"* ]]
}

# --- the line cap ----------------------------------------------------------

@test "oversized file: a node one line past the cap blocks" {
  plant_hub 'See [a](references/a.md).'
  # 401 lines: the first is the heading, the rest filler the checker ignores.
  { printf '# A\n'; for _ in $(seq 400); do printf 'filler\n'; done; } \
    > docs/references/a.md
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"oversized-file"* ]]
  [[ "$output" == *"references/a.md"* ]]
  [[ "$output" == *"401 lines"* ]]
}

@test "oversized file: a node exactly at the cap passes" {
  plant_hub 'See [a](references/a.md).'
  { printf '# A\n'; for _ in $(seq 399); do printf 'filler\n'; done; } \
    > docs/references/a.md
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "clean tree: the gate signs off with the checks it ran" {
  plant_ref "a.md" '# A — decisions D9' '' '**D9 — First**' '' 'Argument.'
  plant_hub 'See [a](references/a.md).' '' '- **D9** — first'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"broken-link"* ]]
  [[ "$output" == *"unstubbed-decision"* ]]
  [[ "$output" == *"stub-without-body"* ]]
  [[ "$output" == *"duplicate-decision"* ]]
  [[ "$output" == *"undefined-decision"* ]]
  [[ "$output" == *"enumeration-drift"* ]]
  [[ "$output" == *"oversized-file"* ]]
  [[ "$output" == *"1 decision"* ]]
}

@test "no docs tree: a missing docs directory is an error, not a silent pass" {
  rm -rf docs
  run "$CHECKER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no docs"* ]]
}

@test "no hub: a missing design.md is an error, not a silent pass" {
  rm -f docs/design.md
  run "$CHECKER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"design.md"* ]]
}

@test "discovery: the checker is executable" {
  [ -x "$PLUGIN_ROOT/scripts/check-docs-links.py" ]
}

@test "discovery: just precommit reaches the checker" {
  # The recipe body between `precommit:` and the next recipe header must name
  # the checker — a mention anywhere else in the justfile would not run it.
  run awk '/^precommit:/{inr=1;next} /^[a-z-]+:/{inr=0} inr' "$PLUGIN_ROOT/justfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"check-docs-links"* ]]
}

@test "real repo: the docs graph reports zero blocking violations" {
  run "$CHECKER" --root "$PLUGIN_ROOT"
  [ "$status" -eq 0 ]
}
