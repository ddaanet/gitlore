# Item 3.1 — code review

Commit reviewed: a59061f. Scope: `scripts/resolve.sh` `compose_merged_indexes`
and its header comment. Fixes applied uncommitted.

## Findings

### Major: fixed. The refusal used `return 1` and depended on errexit

The only call site is `scripts/resolve.sh:270`: a bare
`compose_merged_indexes "$memroot" "$mempath"` in the `continue-after-merge`
case arm, inside the top-level `if [ $# -ge 1 ]; then` body. It is not in an
`if`, `||`, `&&`, `!` or `$(...)` context, and `continue-after-merge` is only
invoked as a process (`bash resolve.sh continue-after-merge`). So GREEN's
`return 1` did abort correctly under `set -euo pipefail`. That was behaviourally
correct but fragile: a designed refusal relied on errexit firing, and nothing at
the call site shows the exit.

Of the two choices the dispatch offered, "`return 1` with a checked call site"
is unsafe. The header already explains why: `compose_merged_indexes … || exit 1`
suspends errexit across the whole body, so a failed `add` would no longer abort.
That leaves `exit 1`, which is what the runbook specifies. It holds in any
calling context except a command substitution, and no caller uses one.

Fix: `return 1` becomes `exit 1`, and the "Returns" paragraph now begins "EXITS
1, before staging anything, when the merge fails its own check … an exit rather
than a return, because the caller cannot check a status without an `||` on the
call." This matches the file's existing "EXITS 1" wording for `push_or_report`.

### Checked: attribution, no finding

- `gitlore_compose_up` returns the problem list from `gitlore_compose_check`
  unfiltered. Rules 1, 4 and 6 print `"$file: …"`, where `$file` is
  `"$mempath/MEMORY.md"` or `"$mempath/$tier/MEMORY.md"`. Here `$mempath` is
  this function's `$memroot`, so the check and the filter build the prefix by
  the same concatenation. The spelling can be relative (`memory`), carry a
  trailing slash (`memory//MEMORY.md` on both sides) or contain spaces, and the
  two sides still match. `merged_tier` is the same relative form the check
  iterates over (`gitlore_tier_paths`).
- The here-string gives the whole of `$composed`. `gitlore_compose_problems_in`
  reads with `IFS= read -r … || [ -n "$line" ]` and matches with a quoted
  `case "$file: "*`, so the path is never read as a pattern.
  `tests/index_compose.bats:1116-1124` covers a spaced path.
- Rules 2 and 3 carry no index-file prefix ("the tier manifest lists…", "root
  index line '…' has a prefix…"), so they never block a memory-root merge. Slice
  5 confirms this.
- rc 2 and rc 0 are untouched: the gate is `[ "$rc" -eq 1 ]`, and a miss falls
  through to the unchanged dispatch.
- Mutation run: the tier-path assignment was mutated so the filter always used
  root `MEMORY.md`. Both slice-1 tests failed at `[ "$status" -eq 1 ]`, so the
  tests depend on the attribution. The SUT was restored and checked with `cmp`.

### Checked: lifecycle, no finding

`gitlore_compose_up` returns 1 from `gitlore_compose_check` before
`gitlore_compose_write`, so on this path nothing is written to the root index.
The refusal comes before every `add` and before the commit, the state-file
clear, the pending-ref delete and the `live` push. The merger's own `add -A`
(the synthesis) stays staged, and `MERGE_HEAD` and the state file are kept. The
"store not inside the memory root" arm returns 0 before the gate, as it did
before this change; it composes nothing, so no check runs there.

### Checked: output and header, no finding

- The header sentence matches the Interfaces block byte for byte.
- Problem lines use `gitlore:   `, like the other arms.
- Plain `>&2` is right: every arm in this function uses it, and the output goes
  to the merger agent that runs the continuation.
- The rewritten "A refusal blocks the merge only when…" paragraph is accurate,
  in present tense and cites no plans. It is consistent with the arms: carrier
  problems block a tier merge; root rules 1, 4 and 6 block a memory-root merge;
  everything else lands, and a tier merge with a root-only problem lands and
  rests the tier.

### Checked: shell hazards, no finding

- No `2>/dev/null`.
- No bash-3.2 constructs: here-string, `local`, `case`.
- `index_problems=$(…)` inside an `if` condition is the intended use of the
  status.
- Whitespace-safe quoting throughout.

### Observation, not fixed: the gate never runs when the root has no `MEMORY.md`

`gitlore_compose_up` (`scripts/lib/index-compose.sh:799-803`) does
`[ -f "$root" ] || return 0` before `gitlore_compose_check`. So in a memory
store with no root index, a tier merge whose carrier has a duplicate pointer
gets rc 0 and lands. The last block of the function then says "The merge is
committed regardless". Read against the Interfaces contract ("exits 1 … when the
merged index fails the check"), that is a gap. The runbook, however, keys the
gate on "`gitlore_compose_up` returns 1", and the function says on purpose that
a rootless store "must not be blocked". Closing the gap means running
`gitlore_compose_check` on a rootless tier merge without sending its rc 1 into
the tier-unadopted arm. That is a design call about whether K4 applies to a
rootless store, so I left it for the lead. No gitlore script creates a root
index when a tier is mounted, so the state can be reached. Nothing in the suite
covers it.

## Verification

- `scripts/run-bats.sh tests/resolve_compose.bats`: 15 passed, 0 failed.
- `scripts/run-bats.sh tests/tier_divergence.bats`: 19 passed, 0 failed.
- `scripts/run-bats.sh tests/resolve_recovery.bats`: 23 passed, 0 failed.
- `scripts/run-bats.sh tests/resolve.bats`: 8 passed, 0 failed.
- `scripts/run-bats.sh tests/git_hook_pre_commit.bats`: 20 passed, 0 failed.
- `shellcheck scripts/resolve.sh`: clean.

## Flags

- REFACTOR-NEEDED: none.
- UNFIXABLE: none.
- Missing tests: none added. The observation above has no test because the fix
  is a design call.
