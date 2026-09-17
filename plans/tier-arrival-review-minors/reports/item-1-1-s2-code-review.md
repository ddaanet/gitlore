# Item 1.1 / slice 2 — code review

**Commit:** 25a6428, `scripts/lib/resolve.sh`. **Verdict:** approved with one
fix applied (uncommitted).

## Findings

### 1. Discriminator coupled to `$remedy` (major) — FIXED

GREEN told the unrepairable arm apart from the transient arms by testing
`[ -n "$remedy" ]` inside the shared `[ -z "$repair" ]` block. That makes "the
refusal is printed" depend on "no arm set a remedy". It is a trap. An arm that
sets its own remedy, even `Run /gitlore:merge again.`, would silently skip
printing the refusal and still pass the one test that exists.

Item 1.2's `mktemp` arm would not trip it. That arm fails before the if/elif
chain and calls the report helper directly. The next arm added to the chain
would trip it.

**Fix:** the unrepairable arm now removes the scratch directory, walks back with
its own remedy and returns 1 inside its own `elif`. The shared tail handles only
transient failures. It always calls
`gitlore_adopt_report_refusal_and_walk_back … "$composed" "Run /gitlore:merge again."`,
under a two-line comment saying so. The cost is one duplicated
`rm -rf -- "$scratch"`. `$remedy` is now read only inside the arm that sets it.

### 2. Report helper comment (minor) — FIXED

"by a repair's transient failure or retry that still finds root, the manifest or
another tier refusing" parsed as the transient failure finding root refusing. It
now reads: "by a repair that fails on something the next take redoes, and by a
repair's retry that still finds root, the manifest or another tier refusing."

### 3. Checks with no finding

- **Own `could not …` line.** Each of the five arms prints its own line before
  the header:
  - arrival read (:1915);
  - pin read (:1918);
  - rewrite (:1920);
  - commit build (`building the repair commit failed.`);
  - `live` advance.
- **Every transient path reaches the helper.** Arrival read, pin read, rewrite
  and commit build each leave `repair` empty. That holds because `repair` starts
  as `""` and the commit-build arm resets it. Each then falls through to the
  shared tail. `live` advance calls the helper itself.
- **Header is correct for transients.** The helper prints the whole `$composed`,
  carrier lines included. That is what the runbook asks for.
- **`set -u`.** `remedy="${6:-}"` covers the two five-argument callers: the
  plain refusal in `gitlore_adopt_tier_into_root` and the retry refusal. An
  empty `$6` reaches `gitlore_adopt_walk_back_tier` as `"${5:-Fix the store…}"`,
  so the default holds.
- **`set -e`/pipefail.** Every helper call carries `|| :` and every failing
  command sits in an `if`/`elif` condition. `scripts/resolve.sh` runs
  `set -euo pipefail`. The one pipeline, `printf | sed`, cannot fail partway.
- **Whitespace.** All expansions are quoted. `$composed` goes through
  `printf '%s\n'`.
- **Scope.** `<live_holds>`, the retry-refusal wording, the checkout-follow arm
  (still a bare `gitlore_adopt_walk_back_tier`) and Item 1.2 are untouched, as
  intended.

## Mutation probes (in place, restored; `cmp` confirmed)

- **A: shared tail reverted** to a bare `gitlore_adopt_walk_back_tier`, applied
  after the fix. The slice test **redded** at line 619, the header assertion.
- **B: `live`-advance arm reverted** to a bare `gitlore_adopt_walk_back_tier`.
  The whole `tests/merge_memory.bats` stays **green**, 37/37. That arm's
  rewiring has no test. The runbook's slices do not include one. A test is a RED
  task, so it is not added in this review. The orchestrator should decide
  whether to add a slice: a `git` stub failing
  `push -q . <sha>:refs/heads/live`, with `GITLORE_GIT_RETRY_SCHEDULE=0`. The
  arrival-read, pin-read and rewrite arms share the tail the commit-build test
  covers, so after the fix they are covered structurally.

## Verification

- `shellcheck scripts/lib/resolve.sh`: clean.
- `scripts/run-bats.sh tests/merge_memory.bats`: 37 passed, 0 failed.

Nothing committed. The working-tree diff is `scripts/lib/resolve.sh` only.

## Refactoring flagged

None.
