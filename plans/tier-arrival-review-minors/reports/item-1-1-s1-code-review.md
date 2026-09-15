# Item 1.1 / slice 1 — code review

**Scope:** `scripts/lib/resolve.sh` from the slice commit: the seventh argument
of `gitlore_adopt_repair_arrival` and its unrepairable arm. Transient arms,
`live_holds` wording, Item 1.2 and later phases are out of scope and untouched.

## Verdict

Correct against the spec after one fix (applied). No critical or major issues.

## Findings

### Minor: the selector was re-implemented inline (FIXED)

The spec defines the other lines as those
`gitlore_compose_problems_in "$tierpath/MEMORY.md"` does not select. GREEN
filtered with an inline `case "$line" in "$tierpath/MEMORY.md: "*)`. That
matched the helper's current rule exactly: the same literal `"$file: "` prefix,
quoted so the path is not read as a pattern. Behaviour did not diverge, but the
selection rule then lived in two places. `gitlore_adopt_tier_into_root` already
uses the helper to decide that the refusal names the carrier. If that rule
changed in the helper, the arm's complement would drift from the selection that
routed the refusal into the arm.

Fix: the loop now calls the helper as a per-line predicate, inside a command
substitution:

```bash
other_lines=$(
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    gitlore_compose_problems_in "$tierpath/MEMORY.md" <<<"$line" >/dev/null && continue
    printf '%s\n' "$line"
  done <<<"$composed"
)
```

The command substitution also removes the one-off
`"${other_lines:+$other_lines$'\n'}$line"` accumulator. That form depends on
`extquote`, which is on by default in bash 3.2 as well, so it was not a
defect, but it is not an idiom used elsewhere in `scripts/`. The `&& continue`
list is exempt from `set -e`, and the function runs under `|| return 1` in any
case.

## Checks

- **Spec conformance.** The call passes `"$composed"` as `$7`, and the header
  doc names it. Other lines print after the `live:MEMORY.md:` lines, under
  `gitlore: the root index could not take tier '<t>''s lines:`. That header
  matches `gitlore_adopt_report_refusal_and_walk_back` word for word, and each
  line takes the `gitlore:   ` prefix. The remedy is the two-fix string when
  other lines exist and unchanged otherwise. Both strings match the runbook
  verbatim.
- **Whitespace safety.** Lines are read with `IFS= read -r` plus the
  unterminated-last-line guard. The prefix match is a quoted literal in the
  helper, so a tier path with spaces or glob characters matches exactly. Nothing
  splits on whitespace.
- **bash 3.2 / BSD.** Here-strings, `$( )` and `sed 's/^/…/'` are all portable.
  `printf | sed` under `pipefail` mirrors the sibling reporter.
- **Wording.** The header and prefix are consistent with the sibling. One
  observation, not changed because the runbook owns the string: "Fix the
  problems listed above in this repo" also sits below the upstream
  `live:MEMORY.md:` lines. The clause after the semicolon disambiguates it.
- **Comment density.** No comment on the new block, in keeping with the
  surrounding arm, and none is needed.
- **Test.** The assertions match the slice: the `live:MEMORY.md:` line, the
  header followed directly by the `memory/MEMORY.md: duplicate pointer path
  dup.md` line, the tail remedy, and no `memory/ddaanet/MEMORY.md:` line
  anywhere. The negative assertion is what catches an unfiltered
  implementation.

## Runs

- Mutation (SUT edited in place, then restored): the predicate was replaced by
  `false`, so carrier lines leak under the header.
  `scripts/run-bats.sh tests/merge_memory.bats --filter 'beside a root duplicate reports both'`
  went **red** at `[[ "$stderr" != *"memory/ddaanet/MEMORY.md:"* ]]`. The
  restore was confirmed by `git diff`, which shows only the fix above.
- `shellcheck scripts/lib/resolve.sh tests/merge_memory.bats`: clean.
- `scripts/run-bats.sh tests/merge_memory.bats` with the fix: 36 passed, 0
  failed.
- Re-run after the mutation restore,
  `scripts/run-bats.sh tests/merge_memory.bats --filter 'repair cannot fix'`:
  2 passed, 0 failed.

Nothing committed.

## Refactoring flagged

None.
