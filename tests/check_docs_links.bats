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
load helpers/check-docs-links

# --- broken links ----------------------------------------------------------

@test "broken link: a pointer to a missing file blocks" {
  plant_decisions 'Arguments in [the gate](references/commit-gate.md).'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken-link"* ]]
  [[ "$output" == *"references/commit-gate.md"* ]]
}

@test "broken link: a pointer that resolves is clean" {
  plant_ref "commit-gate.md" '# The commit gate'
  plant_decisions 'Arguments in [the gate](references/commit-gate.md).'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "broken link: a target inside a code span is prose, not a pointer" {
  plant_decisions 'A composed line reads `- [A](a.md) — hook` in the root index.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "broken link: an http target is not a path" {
  plant_decisions 'See [the issue](https://github.com/anthropics/claude-code/issues/1).'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "broken link: a changelog entry is scanned too" {
  mkdir -p docs/changelog
  printf '# An entry\n\nSee [the design](../design.md) and [gone](gone.md).\n' \
    > docs/changelog/2026-01-01-a.md
  plant_decisions 'Nothing here.'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"gone.md"* ]]
}

# --- orphans ---------------------------------------------------------------

@test "orphan: a node nothing points at warns without blocking" {
  plant_ref "a.md" '# A' '' 'A body.'
  plant_decisions 'Nothing points at a.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphan-reference"* ]]
  [[ "$output" == *"a.md"* ]]
}

@test "orphan: a citation from outside docs counts as reachable" {
  plant_ref "a.md" '# A' '' 'A body.'
  plant_decisions 'Nothing points at a.'
  mkdir -p memory/ddaanet
  printf 'Full evidence in `docs/references/a.md`.\n' > memory/ddaanet/f.md
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"orphan-reference"* ]]
}

@test "orphan: a sibling-relative link from another node counts as reachable" {
  # Nodes link each other as `[b](b.md)`, with no `references/` in the target.
  plant_ref "a.md" '# A' '' 'A body.'
  plant_ref "b.md" '# B' '' 'Argued in [a](a.md).'
  plant_decisions 'See [b](references/b.md).'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"orphan-reference"* ]]
}

@test "orphan: a bare basename from outside the node directory does not reach it" {
  # `[a](a.md)` in a plan resolves next to the plan, not to the node.
  plant_ref "a.md" '# A' '' 'A body.'
  plant_ref "b.md" '# B' '' 'Unrelated.'
  plant_decisions 'See [b](references/b.md).'
  mkdir -p plans
  printf 'See [a](a.md).\n' > plans/p.md
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphan-reference"* ]]
  [[ "$output" == *"references/a.md"* ]]
}

# --- scope, suppression, reporting -----------------------------------------

@test "suppression: a hygiene-ok marker clears the line it sits on" {
  plant_decisions 'A pointer to [nowhere](references/gone.md). <!-- hygiene-ok -->'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "whitespace: a docs path containing a space is scanned, not split" {
  plant_ref "a b.md" '# A B — decisions D9' '' '**D9 — First**' '' 'Argument.'
  plant_decisions 'See [a b](<references/a b.md>).'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a b.md"* ]]
  [[ "$output" == *"unstubbed-decision"* ]]
}

# --- the line cap ----------------------------------------------------------

@test "oversized file: a node one line past the cap blocks" {
  plant_decisions 'See [a](references/a.md).'
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
  plant_decisions 'See [a](references/a.md).'
  { printf '# A\n'; for _ in $(seq 399); do printf 'filler\n'; done; } \
    > docs/references/a.md
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "clean tree: the gate signs off with the checks it ran" {
  plant_ref "a.md" '# A — decisions D9' '' '**D9 — First**' '' 'Argument.'
  plant_decisions 'See [a](references/a.md).' '' '- **D9** — first'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"broken-link"* ]]
  [[ "$output" == *"unstubbed-decision"* ]]
  [[ "$output" == *"stub-without-body"* ]]
  [[ "$output" == *"duplicate-decision"* ]]
  [[ "$output" == *"undefined-decision"* ]]
  [[ "$output" == *"enumeration-drift"* ]]
  [[ "$output" == *"delegation-drift"* ]]
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
  plant_decisions 'Nothing yet.'
  rm -f docs/design.md
  run "$CHECKER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"design.md"* ]]
}

@test "no decisions index: a missing decisions.md is an error, not a silent pass" {
  run "$CHECKER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"decisions.md"* ]]
}

@test "conclusions live in the index: a bullet in design.md concludes nothing" {
  plant_ref "a.md" '# A — decisions D9' '' '**D9 — First**' '' 'Argument.'
  plant_decisions 'See [a](references/a.md).'
  printf -- '- **D9** — first\n' >> docs/design.md
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unstubbed-decision"*"references/a.md"* ]]
  [[ "$output" == *"decisions.md"* ]]
}

@test "undefined decision: a citation in the hub is checked against the index" {
  plant_decisions 'Nothing yet.'
  printf 'The redirect is a shim (D10).\n' >> docs/design.md
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"undefined-decision"*"docs/design.md"*"D10"* ]]
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
