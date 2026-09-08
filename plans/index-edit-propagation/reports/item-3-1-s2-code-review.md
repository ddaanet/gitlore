# Item 3.1 slice 2 — code review

Three fixes applied to the two hooks. One defect is reported and deliberately
left standing (slice 4 owns its RED). One defect is **in-scope-unfixable** and
needs a decision before this phase closes: the two `PostToolBatch` hooks share
one relay marker name per agent, so within a single subagent batch the second
hook to run truncates the first hook's staged report. Demonstrated by hand-run,
not inferred.

## Findings

### F1 — Two hooks, one marker: the compose hook silently destroys the sync hook's relayed report (in-scope-unfixable)

`hooks/hooks.json` registers both `index-sync-post.sh` (`:82`) and
`index-compose.sh` (`:98`) on `PostToolBatch`, so both fire on the same batch.
Both now call `gitlore_relay_write "$mempath" "$agent_id" …`, which resolves to
the same path — `gitlore-relay-<agent_id>` — and whose single redirect
truncates. In a subagent batch that edits `MEMORY.md`, the sync hook writes its
report, the compose hook overwrites it, and the parent receives only the compose
report. The frontmatter-sync report — the one that tells the actor its authored
`description:` was clobbered — is lost exactly on the path the relay exists to
serve.

Hand-run, both hooks driven keyed as `a1` over one batch (`pre` + a root index
edit adding `p.md`, then `index-sync-post.sh`, then `index-compose.sh`):

```
--- marker after sync-post ---
--- gitlore-relay-sysmsg ---
gitlore: reset frontmatter to match MEMORY.md (1 file)
...
--- marker after compose (same batch) ---
--- gitlore-relay-sysmsg ---
gitlore: recomposed tier pointers (1 index)
...
--- does the marker still hold the sync report? ---
SYNC REPORT LOST
```

The same mechanism loses a report across *batches*: a subagent that edits the
index in two successive batches has its first batch's marker truncated by its
second, since nothing parent-side runs in between (the parent is blocked inside
the `Task` call for the subagent's whole lifetime).

**Why I did not fix it.** Every available fix leaves this slice's scope:

- Distinguishing the key at the call site (`"$agent_id-compose"`) changes the
  marker basename, and `tests/cc_hook_index_compose.bats` asserts
  `[ -f "$(gitlore_relay_marker_file memory a1)" ]` after a keyed compose run —
  a frozen test.
- Making `gitlore_relay_write` append rather than truncate changes
  `scripts/lib/index-sync.sh`, committed and frozen, and changes the file format
  the frozen slice-1 contract cases pin.

Fix 3 below narrows the window substantially — neither hook stages anything now
unless it has a report — but the loss remains whenever both hooks report in one
batch, which is the ordinary case for a store with a tier mounted (the fixture
above is exactly `make_parent_with_memory` + one `ddaanet` tier).

Recommendation for the orchestrator: this is a decision, not an edit. Either the
marker gains a per-source component in its key (and the drain's framing line
learns to render `agent a1` from a compound suffix), or `gitlore_relay_write`
becomes append-with-truncate-on-first-write-per-run. Both touch frozen artifacts
and want their own RED.

### F2 — A keyed run with nothing to report staged an empty marker (FIXED)

Reachable in both hooks — the test review already established the
empty-own-report state is reachable in each, and both hooks called
`gitlore_relay_write` unconditionally in the keyed branch. The drain frames
every marker it finds, so an empty marker reached the parent as framing wrapped
around nothing, on a batch the parent would otherwise have passed in silence.

Before the fix, a keyed compose run whose composition found nothing left to do:

```
--- marker contents ---
--- gitlore-relay-sysmsg ---

--- gitlore-relay-ctx ---

--- unkeyed parent run ---
RAW: {
  "systemMessage": "--- gitlore-relay agent a1 ---\n\n",
  "suppressOutput": true,
  "hookSpecificOutput": {
    "hookEventName": "PostToolBatch",
    "additionalContext": "--- gitlore-relay agent a1 ---\n\n"
  }
}
```

After the fix the same fixture writes no marker and the parent emits nothing.

The guard is `[ -n "$GITLORE_COMPOSE_SYSMSG" ]` / `[ -n "$sysmsg" ]` — the same
condition each hook's own emission guard applies, which is what makes it the
right one: a run that has nothing to say to its own user has nothing to relay to
the parent's. The ctx half needs no guard: `gitlore_compose_and_report` leaves
`GITLORE_COMPOSE_CTX` empty whenever `GITLORE_COMPOSE_SYSMSG` is, and in
`index-sync-post.sh` every block that sets a `ctx` sets a `sysmsg` with it
(`failed` sets a sysmsg alone, never a ctx alone).

**No test pins this fix.** The suites were green before it and are green after.
Tests are out of scope for this review, so the gap is reported rather than
closed; it belongs to this slice.

### F3 — Shipped source cited a memory file (FIXED)

Both new comment blocks said `(measured, see hook-output-channels)`.
`memory/ddaanet/hook-output-channels.md` reaches the tree through a submodule
gitlink and is not distributed, so a shipped comment may not cite it — the same
rule that made Item 3.1 slice 1's code review strip a `plans/` citation out of
`scripts/lib/index-sync.sh`. Replaced with `(measured under CC 2.1.261)`,
verbatim the wording the committed `gitlore_relay_*` helpers use, which is what
Item 4.1 will back-fill a `D<n>` id into.

### F4 — Compose's fold used `$'\n'` inside `${…:+…}` (FIXED)

`index-compose.sh` joined with
`${GITLORE_COMPOSE_SYSMSG:+$GITLORE_COMPOSE_SYSMSG$'\n'}`.
`gitlore_compose_and_report`, which is the function producing the very variables
being appended to, uses the same `${var:+…}` shape with a **literal** newline
(`scripts/lib/index-compose.sh:721,731,741,752`), and `index-sync-post.sh`'s new
block matches its own file's four-times-used `if [ -n "$sysmsg" ]; then …`
idiom. Whether `$'…'` is processed inside `${…}` under double quotes is a
bash-version question the repo has no reason to be asking on a macOS/bash-3.2
target; the literal newline removes it and makes the join byte-identical to the
idiom it claims to match. Behaviour on bash 5.2 is unchanged (both suites green
before and after).

### F5 — A failed relay write costs the entire report (REPORTED, NOT FIXED — slice 4)

Confirmed by hand-run, as instructed, with
`mkdir "$(gitlore_relay_marker_file memory a1)"` and a keyed compose run over an
index edit that composes:

```
rc=1
stdout=[]
stderr:
/Users/david/code/gitlore/tests/../scripts/lib/index-sync.sh: line 137: \
  /tmp/claude-1000/gitlore-test.UzHU6T/.git/modules/gitlore-memory/gitlore-relay-a1: Is a directory
```

The hook exits 1 with **empty stdout** — the subagent's own compose report is
destroyed along with the relay. This is what slice 4's
`a failed relay write leaves the subagent's own report intact` must red against,
and it does. Left standing.

Fix 2 changes the *reachability* of this path but not its behaviour: a keyed run
now only reaches `gitlore_relay_write` when it has a report, which is exactly
the condition slice 4's case sets up. The slice-4 RED is unaffected.

### F6 — Slice 4's drain-side case will be born green (informational)

`an unkeyed run survives a non-file squatting on a marker name` already passes
against the current tree, because `gitlore_relay_drain`'s `-type f` (slice 1,
committed) skips the directory:

```
rc=0
stdout=[{ "systemMessage": "gitlore: recomposed tier pointers (1 index)", … }]
stderr:
```

The runbook anticipates this
(`slice 1 has no case that makes a directory marker`), but the case as specified
cannot red by absence — it will need the same mutation-red shape slice 1's
`_gitlore_agent_suffix` case used (back the `-type f` out, red, restore).
Flagging it now so slice 4's RED dispatch is not surprised.

### F7 — `gitlore_relay_drain`'s `rm -f` is a new abort path in the unkeyed branch (reported, frozen code)

`gitlore_relay_drain` ends each loop iteration with a bare `rm -f "$marker"`.
The hooks call the drain bare under `set -euo pipefail`, so a `rm` that fails
for a reason `-f` does not swallow — a read-only gitdir — aborts the hook after
the marker's contents have been read and before any JSON is written, losing both
the relay and the hook's own report. Same shape as F5, on the drain side.
`scripts/lib/index-sync.sh` is frozen, so this is reported, not fixed. It is
narrower than F5 (a read-only gitdir already fails composition itself with rc 2
upstream, per the runbook's own note on slice 4's fixture choice), which is why
I rank it below F5 rather than beside it.

## Mutation table

Every mutation applied **in place** to the working-tree SUT, run against
`tests/cc_hook_index_compose.bats` + `tests/index_sync.bats` (99 cases), then
restored. Tests were never edited or relocated. Baseline: 99 passed, 0 failed.

| # | mutation | hook | result | cases that red |
|---|---|---|---|---|
| m1a | fold moved **after** the emission guard | compose | **RED 3** | `an unkeyed compose run folds in the marker and removes it`; `… with no report of its own still emits the relay`; `… folds in a marker a keyed run wrote` |
| m1b | fold moved **after** the emission guard | sync | **RED 2** | `an unkeyed index-sync run folds in the marker`; `… with no report of its own still emits the relay` |
| m2a | `gitlore_relay_write` → hand-rolled `printf` of the raw body to `gitlore_relay_marker_file`'s path | compose | **RED 1** | `an unkeyed compose run folds in a marker a keyed run wrote` |
| m2b | same | sync | **RED 1** | `a keyed index-sync run writes its replacement report to a marker` |
| m3a | keyed branch writes the marker but suppresses the hook's own emission | compose | **RED 2** | `a keyed compose run writes a marker and still emits its own json`; `a subagent's compose consumes its own baseline, not the main thread's` |
| m3b | same | sync | **RED 1** | `a keyed index-sync run writes its replacement report to a marker` |
| m4a | unkeyed branch folds `GITLORE_RELAY_SYSMSG` only, never `…_CTX` | compose | **RED 3** | all three unkeyed compose relay cases |
| m4b | unkeyed branch folds `…_CTX` only, never `…_SYSMSG` | compose | **RED 3** | all three unkeyed compose relay cases |
| m4c | folds sysmsg only | sync | **RED 2** | both unkeyed index-sync relay cases |
| m4d | folds ctx only | sync | **RED 2** | both unkeyed index-sync relay cases |
| m5a | keyed branch **also** drains | compose | **RED 2** | `a keyed compose run writes a marker and still emits its own json`; `… folds in a marker a keyed run wrote` |
| m5b | unkeyed branch **also** writes | compose | **RED 2** | `an already-composed store reports nothing`; `an unkeyed compose run with no report of its own still emits the relay` |
| m5c | keyed branch **also** drains | sync | **RED 1** | `a keyed index-sync run writes its replacement report to a marker` |
| m5d | unkeyed branch **also** writes | sync | **RED 1** | `post: does NOT re-warn the SAME session on a later over-threshold batch` |
| m6a | keyed/unkeyed test inverted (`[ -z … ]`) | compose | **RED 4** | all four compose relay cases |
| m6b | keyed/unkeyed test inverted | sync | **RED 3** | all three sync relay cases |
| m7a | `[ -n "$GITLORE_RELAY_SYSMSG" ]` guard dropped (`if true`) | compose | **GREEN — gap** | — |
| m7b | same guard dropped | sync | **GREEN — gap** | — |

**m7a/m7b ship green — the one gap the round found.** With no marker on disk the
drain leaves both variables empty, so dropping the guard appends the empty
string; the only observable is a trailing newline (compose) or a trailing
newline plus a blank line (sync) on the emitted channels. Every assertion in
both suites is a substring match, so none can see it. The guard is correct as
written and stays; the gap is cosmetic-severity and belongs to this slice, but I
do not recommend a test for it — pinning a trailing newline would pin wording
the suite deliberately does not pin elsewhere.

**m5d is caught only incidentally.** The "unkeyed branch must not write"
property reds on the budget-nudge re-warn case, not on a relay case: the stray
marker is folded back on the next batch and re-surfaces the once-per-episode
warning. It is caught, but by a case that is not about the relay, so a future
edit to that case could open the gap. Belongs to this slice; noted, not closed.

Two mutations the dispatch asked about were merged into the table rather than
run twice: "make the keyed branch write the marker but suppress the hook's own
emission" is m3a/m3b, and the two halves of "keyed also drains / unkeyed also
writes" are m5a–m5d.

## The specific checks

1. **Stdout is exactly one JSON object.** No new path writes to stdout.
   `gitlore_relay_marker_file`'s `rev-parse` and the drain's
   `rev-parse --absolute-git-dir` are both inside command substitutions;
   `gitlore_relay_write`'s only output is the redirect into the marker file, and
   its failure diagnostic goes to stderr (F5's transcript shows it there);
   `find`, `awk`, `sort` and `rm -f` inside the drain are all either NUL-piped
   into a `read` loop, captured, or silent. Verified end to end by probe D,
   whose stdout is one object and whose stderr is empty.
2. **`set -euo pipefail`.** `GITLORE_COMPOSE_SYSMSG`/`_CTX` are assigned on
   every path through `gitlore_compose_and_report`
   (`scripts/lib/index-compose.sh:794,796`), which the hook calls bare at `:66`,
   so the `set -u` expansions at the keyed branch are safe.
   `GITLORE_RELAY_SYSMSG`/`_CTX` are assigned in `gitlore_relay_drain`'s first
   two statements, ahead of every early `return`, and are read only inside the
   branch that called it — the keyed branch never expands them, which is correct
   and would be a `set -u` abort if it did. In `index-sync-post.sh`,
   `sysmsg`/`ctx` are initialised at `:186-187` and `agent_id` at `:23`. The two
   new abort paths under errexit are F5 (the write, excluded) and F7 (the
   drain's `rm -f`, frozen code).
3. **Join style.** Fixed in compose (F4); `index-sync-post.sh` already matched
   its own file. A relayed block cannot run into the hook's own last line —
   compose joins with one newline, sync with one newline, and the drain's blocks
   begin with their framing line. No leading blank line: when the hook's own
   report is empty, `${var:+…}` and `if [ -n "$sysmsg" ]` both contribute
   nothing and the relay stands alone. One residual, inherited from the frozen
   drain: every block it builds ends with a newline, so a relayed emission
   always carries one trailing newline on both channels. Cosmetic, and jq
   encodes it faithfully.
4. **Nesting and lifecycle.** The keyed branch does not drain, so a nested
   subagent's marker accumulates until a parent-side run — which is the design
   (`the next parent-side run folds the markers into its own report and removes them`),
   and m5a/m5c red a keyed branch that drains. Nothing double-folds: the drain
   `rm -f`s each marker in the same iteration that folds it, and m5b/m5d red an
   unkeyed branch that also writes. No path writes a marker and then drains its
   own. Cross-agent clobbering is impossible (distinct ids);
   **same-agent clobbering across hooks and across batches is F1**.
5. **Early exits.** The insertion adds no new early exit. It sits below every
   guard in both hooks, so the drain is reached only on a run that has already
   established it got past `[ -f "$stamp" ]` / `[ -f "$stashfile" ]` and the
   change comparison, and only on the `agent_id`-empty branch — i.e. only when
   the run is established parent-side. The accepted residual stands unchanged: a
   batch that exits upstream strands a pending marker until slice 3's
   SessionStart backstop.
6. **Style.** Memory citation removed (F3). Comment density matches both files,
   which comment their rejected alternatives at this length throughout. No new
   definitions, so "entry points first" does not bite. No compat shim. No
   `plans/` or `memory/` citation remains — `grep` over both hooks for
   `hook-output-channels`, `plans/` and `memory/ddaanet` returns nothing.

## Scope

Touched: `scripts/cc-hooks/index-compose.sh`,
`scripts/cc-hooks/index-sync-post.sh`, and this report. Nothing else. The two
test files show the same 129 / 109 insertions they had on arrival — no test was
edited, and the scratch bats file the probes ran from was deleted, as was the
mutation scratch directory. Nothing committed; the tree is dirty and unstaged.
No `just` recipe was run.

## Checks that passed, by name

- `git diff --stat` after restoring the SUT from the mutation round — only the
  four expected files, tests unchanged at 129 / 109 insertions, no deletions.
- `scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/index_sync.bats` —
  99 passed, 0 failed (baseline before mutations, and again after the fixes).
- `scripts/run-bats.sh tests/cc_hook_session_start.bats tests/cc_hook_add_tier.bats tests/index_compose.bats tests/cc_hook_post_tool_use.bats`
  — 106 passed, 0 failed.
- `shellcheck -s bash scripts/cc-hooks/index-compose.sh scripts/cc-hooks/index-sync-post.sh`
  — clean.
- `scripts/lint-shell.sh` — 137 files clean.
- Mutation round, 18 in-place mutations over both hooks — 16 red, 2 green
  (m7a/m7b), table above.
- Hand-run probes A–D against real hook invocations — F1, F2, F5 and F6
  reproduced; A and B re-run after the fixes, B resolved and A confirmed
  outstanding.
- `grep` over both hooks for `hook-output-channels`, `plans/`, `memory/ddaanet`
  — no match.
