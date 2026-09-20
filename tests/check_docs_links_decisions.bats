#!/usr/bin/env bats
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
# Planted file contents carry backticked spans on purpose — fixtures for the
# checker to read, not expansions this suite wants.
# shellcheck disable=SC2016
#
# The decisions-graph checks: stubs, bodies, delegation, duplicates, and a
# node's own decision enumeration against its title.

load helpers/setup
load helpers/check-docs-links

# --- decisions: stubs and bodies -------------------------------------------

@test "unstubbed decision: a body with no conclusion line in the hub blocks" {
  plant_ref "commit-gate.md" '# The commit gate — decisions D9' '' \
    '**D9 — A sub-agent synthesizes the merge**' '' 'The argument.'
  plant_decisions 'Arguments in [the gate](references/commit-gate.md).'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unstubbed-decision"* ]]
  [[ "$output" == *"D9"* ]]
}

@test "unstubbed decision: a body with a hub bullet is clean" {
  plant_ref "commit-gate.md" '# The commit gate — decisions D9' '' \
    '**D9 — A sub-agent synthesizes the merge**' '' 'The argument.'
  plant_decisions 'Arguments in [the gate](references/commit-gate.md).' '' \
    '- **D9** — a sub-agent synthesizes the merge'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "unstubbed decision: a cluster sub-decision the hub delegates is concluded in its own node" {
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9, D10' '' \
    '- Composition — **D10** the tier manifest' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.'
  plant_decisions 'Sub-decisions (D10) in [tiers](references/tiered-memory.md).' '' \
    '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "unstubbed decision: a self-summary the hub never delegated does not conclude it" {
  # A node summarizing itself is how a hub bullet goes missing unnoticed: only
  # a delegation line in the hub licenses the node's summary to stand in.
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9, D10' '' \
    '- Composition — **D10** the tier manifest' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.'
  plant_decisions 'See [tiers](references/tiered-memory.md).' '' '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unstubbed-decision"* ]]
  [[ "$output" == *"D10"* ]]
}

@test "unstubbed decision: a wrapped summary bullet still concludes what its continuation lines name" {
  # `format-docs` hard-wraps a cluster summary, so a sub-decision's `**D10**`
  # can sit on an indented continuation line rather than the `- ` line itself.
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9, D10' '' \
    '- Composition — **D9** tiered memory, argued at length here ·' \
    '  **D10** the tier manifest' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.'
  plant_decisions 'Sub-decisions (D10) in [tiers](references/tiered-memory.md).' '' \
    '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "delegation: a wrapped delegation line covers the numbers on its continuation" {
  # `(D10,` on one line and `D11) in [..](..)` on the next, as format-docs
  # leaves it.
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9–D11' '' \
    '- Composition — **D10** the manifest · **D11** the ordering' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.' '' \
    '**D11 — The ordering**' '' 'The argument.'
  plant_decisions 'The sub-decisions conclude in each node: composition (D10,' \
    'D11) in [tiers](references/tiered-memory.md).' '' \
    '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "delegation: a range covers every number between" {
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9–D11' '' \
    '- Composition — **D10** the manifest · **D11** the ordering' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.' '' \
    '**D11 — The ordering**' '' 'The argument.'
  plant_decisions 'Sub-decisions (D10–D11) in [tiers](references/tiered-memory.md).' '' \
    '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "delegation drift: a delegated number the node does not summarize blocks" {
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9, D10' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.'
  plant_decisions 'Sub-decisions (D10) in [tiers](references/tiered-memory.md).' '' \
    '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"delegation-drift"* ]]
  [[ "$output" == *"D10"* ]]
}

@test "delegation drift: a delegation to a node that argues it elsewhere blocks" {
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9' '' \
    '- Composition — **D10** the tier manifest' '' \
    '**D9 — Tiered memory**' '' 'The argument.'
  plant_ref "elsewhere.md" '# Elsewhere — decisions D10' '' \
    '- **D10** the tier manifest' '' \
    '**D10 — The tier manifest**' '' 'The argument.'
  plant_decisions 'Sub-decisions (D10) in [tiers](references/tiered-memory.md)' \
    'and [e](references/elsewhere.md).' '' '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"delegation-drift"* ]]
  [[ "$output" == *"D10"* ]]
}

@test "duplicate conclusion: a number both delegated and given a hub bullet blocks" {
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9, D10' '' \
    '- Composition — **D10** the tier manifest' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.'
  plant_decisions 'Sub-decisions (D10) in [tiers](references/tiered-memory.md).' '' \
    '- **D9** — tiered memory' '- **D10** — the tier manifest'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate-conclusion"* ]]
  [[ "$output" == *"D10"* ]]
}

@test "unstubbed decision: a summary in some other node does not conclude it" {
  plant_ref "tiered-memory.md" '# Tiered memory — decisions D9, D10' '' \
    '**D9 — Tiered memory**' '' 'The argument.' '' \
    '**D10 — The tier manifest**' '' 'The argument.'
  plant_ref "elsewhere.md" '# Elsewhere' '' '- Composition — **D10** the tier manifest'
  plant_decisions 'See [tiers](references/tiered-memory.md) and [e](references/elsewhere.md).' \
    '' '- **D9** — tiered memory'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unstubbed-decision"* ]]
  [[ "$output" == *"D10"* ]]
}

@test "stub without body: a hub bullet whose argument lives nowhere blocks" {
  plant_decisions '- **D9** — a sub-agent synthesizes the merge'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stub-without-body"* ]]
  [[ "$output" == *"D9"* ]]
}

@test "stub without body: a decision stated whole in the hub needs no node" {
  plant_decisions '**D9 — A sub-agent synthesizes the merge**' '' \
    'Stated here in full, with its argument.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "duplicate decision: one number with a body in two nodes blocks" {
  plant_ref "a.md" '# A — decisions D9' '' '**D9 — First**' '' 'Argument.'
  plant_ref "b.md" '# B — decisions D9' '' '**D9 — Second**' '' 'Argument.'
  plant_decisions 'See [a](references/a.md) and [b](references/b.md).' '' \
    '- **D9** — a sub-agent synthesizes the merge'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate-decision"* ]]
}

@test "duplicate conclusion: one number stubbed twice in the hub blocks" {
  plant_ref "a.md" '# A — decisions D9' '' '**D9 — First**' '' 'Argument.'
  plant_decisions 'See [a](references/a.md).' '' \
    '- **D9** — a sub-agent synthesizes the merge' \
    '- **D9** — and again, from an earlier grouping'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate-conclusion"* ]]
}

@test "undefined decision: a citation with no decision behind it blocks" {
  plant_decisions 'Both reduce to one shape (D77).'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"undefined-decision"* ]]
  [[ "$output" == *"D77"* ]]
}

@test "undefined decision: a citation inside a code span is not a citation" {
  plant_decisions 'The fixture writes `D77` into the manifest.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

# --- decisions: a node's own enumeration -----------------------------------

@test "enumeration drift: a title claiming a decision the node lacks blocks" {
  plant_ref "a.md" '# A — decisions D9, D10' '' '**D9 — First**' '' 'Argument.'
  plant_decisions 'See [a](references/a.md).' '' '- **D9** — first'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"enumeration-drift"* ]]
  [[ "$output" == *"D10"* ]]
}

@test "enumeration drift: a body the title omits blocks too" {
  plant_ref "a.md" '# A — decisions D9' '' '**D9 — First**' '' 'Argument.' '' \
    '**D10 — Second**' '' 'Argument.'
  plant_decisions 'See [a](references/a.md).' '' '- **D9** — first' '- **D10** — second'
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
  plant_decisions 'See [a](references/a.md).' '' \
    '- **D9** — first' '- **D10** — second' '- **D11** — third'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "enumeration: a node with no decisions in its heading is not enumerated" {
  plant_ref "a.md" '# Auto-memory retrieval' '' 'A method and its findings.'
  plant_decisions 'See [a](references/a.md).'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}
