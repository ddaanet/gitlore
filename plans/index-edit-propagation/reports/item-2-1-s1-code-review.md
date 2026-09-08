# Item 2.1 slice 1 — code review

Scope reviewed: `scripts/lib/index-sync.sh`, the two helpers the slice changed.
Read-only for judgement: `tests/index_sync.bats` (the four new cases), the four
consumers under `scripts/cc-hooks/`, `plans/index-edit-propagation/outline.md`
§C, the runbook's Item 2.1, this slice's RED / test-review / GREEN reports, and
`memory/ddaanet/hook-input-schema.md`.

One change applied. It is a change to the shipped contract's *spelling*, not to
the contract the slice's tests assert, so it is called out first.

## Major — the agent id reached `--git-path` unvalidated

**Applied.** `${2:+-$2}` spliced a raw hook-payload field straight into the
`rev-parse --git-path` argument. `--git-path` does no normalising whatsoever —
it returns `<gitdir>/<name>` verbatim, which I confirmed rather than assumed:

```
$ git -C "$d" rev-parse --git-path 'gitlore-index-preimage-../../../etc/passwd'
.git/gitlore-index-preimage-../../../etc/passwd
$ git -C "$d" rev-parse --git-path 'gitlore-index-preimage-/etc/passwd'
.git/gitlore-index-preimage-/etc/passwd
$ git -C "$d" rev-parse --git-path "$(printf 'gitlore-x-a\nb')"
.git/gitlore-x-a
b
```

so a `/` or a `..` component in the id walks the returned path out of the
gitdir, and the consumers then act on it: `cp "$index" "$stash"`
(`scripts/cc-hooks/index-sync-pre.sh:57`), `rm -f "$stashfile"`
(`index-sync-post.sh:39,146`), `rm -f "$stamp"` (`index-compose.sh:50`),
`rm -f "$(gitlore_compose_stamp_file "$mempath")"` (`add-tier-batch.sh:75`). A
newline in the id yields a two-line name, which no consumer handles.

The fix collapses everything outside `[A-Za-z0-9-]` to `_` in a new private
`_gitlore_agent_suffix`, placed after its two callers per the file's
entry-points-first ordering:

```sh
_gitlore_agent_suffix() {
  [ -n "${1:-}" ] || return 0
  printf -- '-%s' "$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9-' '_')"
}
```

Both helpers now call
`…"gitlore-index-preimage$(_gitlore_agent_suffix "${2:-}")"`.

### Why in the helpers, not in slices 2–4's consumers, and not nowhere

**Verdict: the guard belongs here, in the helpers.** Three reasons.

1. **The file already does exactly this, three functions down.**
   `_gitlore_nudge_file` (`scripts/lib/index-sync.sh:182-186`) takes the session
   id — the same payload, the same trust level, the same destination — and runs
   `LC_ALL=C sed 's/[^A-Za-z0-9-]/_/g'` over it before interpolating into
   `rev-parse --git-path`. Sanitizing one harness-supplied id and not the other,
   in one file, is an inconsistency with no stated reason behind it. The
   precedent also settles *where*: the helper sanitizes, not its callers.
2. **One choke point instead of four, growing to five.** Slices 2–4 add the
   `agent_id` read to `index-sync-pre.sh`, `index-sync-post.sh`,
   `index-compose.sh` and `add-tier-batch.sh`; Phase 3 (Item 3.1) adds a sixth
   `gitlore-…` marker helper keyed by the same id. Guarding at the consumers
   means four places to get right now and a fifth later, and a marker that
   sanitized differently from the pre-image would disagree about which agent a
   file belongs to.
3. **The reachable failure is an upstream format change, not an attacker.** I
   checked the harness claim against `memory/ddaanet/hook-input-schema.md`
   rather than taking it: `agent_id` is a top-level optional stdin field present
   only inside a subagent, minted by Claude Code, and Claude Code uses it as a
   filename component itself (`<session-dir>/subagents/agent-<agent_id>.jsonl`).
   So today's ids are `[A-Za-z0-9-]` and there is no live exploit — the model
   cannot set this field. What is plausible is a future composite id
   (`type/uuid`, a space-bearing label), which would make these hooks `cp` onto
   and `rm -f` a path outside the gitdir, silently, since both are inside
   `PostToolBatch` hooks that report nothing on this path. That is cheap to
   foreclose and removes nothing.

**"Nowhere" was the alternative I weighed and rejected**: it rests entirely on
"the harness generates it", which is true today, is not asserted anywhere, and
is the one assumption the code has no way to notice breaking.

### What the guard changes, and what it does not

- `agent-7` (slice 1's fixture) and `a1` (slices 2–4's) contain only
  `[A-Za-z0-9-]` and pass through byte for byte, so no test in the suite — this
  slice's or the later slices' as specified in the runbook — changes meaning.
- The item's wording "non-empty appends `-<agent_id>`" now holds modulo the
  character class. That is stated in the code comment, not left implicit.
- The mapping is not injective: two ids differing only outside `[A-Za-z0-9-]`
  would collide onto one keyed file and race exactly as the unkeyed names do.
  Stated as a residual in the comment per the repo's "bound it rather than imply
  full coverage" rule; unreachable from any id shape that occurs.
- `tr -c`, not `_gitlore_nudge_file`'s `sed`, because `sed` is line-oriented and
  passes an embedded newline through unchanged
  (`printf 'a\nb' | sed 's/[^A-Za-z0-9-]/_/g'` → two lines;
  `printf 'a\nb' | tr -c 'A-Za-z0-9-' '_'` → `a_b`). `tr -c` is already used in
  the repo (`scripts/lib/edit-weld.sh:21`), so this is not a new dependency.
- If you would rather this land in a later slice or as its own item, reverting
  is mechanical: restore `${2:+-$2}` in the two helpers and drop
  `_gitlore_agent_suffix`.

**Flagged, not fixed:** `_gitlore_nudge_file`'s own `sed` has the same newline
hole for the session id. It serves a different feature, is untouched by this
slice, and session ids are UUIDs, so folding an unrelated behavioural change
into this slice's commit is the wrong trade. It is a one-line swap whenever that
function is next opened.

## Assessed, no defect — `${2:+…}` / `${2:-…}` under `set -u`

The dispatch asked for this to be confirmed rather than assumed. It is safe, and
my replacement is the same exempt class, so the answer is unchanged by the fix.

- `${parameter:+word}` and `${parameter:-word}` are the two forms POSIX
  explicitly exempts from `set -u`; unset `$2` expands to the alternative
  without an "unbound variable" error.
- Verified empirically:
  `bash -c 'set -euo pipefail; f() { printf "[%s]\n" "name${2:+-$2}"; }; f one'`
  → `[name]`, exit 0. Same under `sh -c 'set -u; …'`.
- The form is already established in this file — `_gitlore_nudge_file`'s
  `${2:-nosession}` (`scripts/lib/index-sync.sh:184`) and
  `gitlore_index_largest`'s `${2:-5}` (`:225`) — though I checked their call
  sites rather than assuming: both are always called with two arguments
  (`index-sync-post.sh:164`, `plugin-upgrade-batch.sh:55`,
  `tests/index_sync.bats:724,747`), so they establish the idiom, not an
  absent-`$2` exercise.
- The absent-`$2`-under-`set -u` case *is* exercised, by these two helpers
  themselves: all four consumers run `set -euo pipefail` and call them with one
  argument (`index-sync-pre.sh:2,40-41`, `index-sync-post.sh:2,30`,
  `index-compose.sh:2,32`, `add-tier-batch.sh:2,75`), and
  `tests/index_sync.bats` drives those hooks end to end. The 66/0 run is that
  evidence.
- **Caveat, stated rather than glossed:** this box has bash 5.2 only
  (`/bin/bash`, `/usr/bin/bash`; no 3.2 binary), so the macOS bash 3.2 leg rests
  on the POSIX exemption, not on a run. The known bash-3.2 `set -u` trap is
  `"$@"`/`"$*"` with no positional parameters, which neither form touches.
- Post-fix, all four call sites in these helpers are the `${2:-}` form, and
  `_gitlore_agent_suffix` re-guards with `${1:-}` so it is safe called with no
  argument at all. Confirmed by running both helpers under `set -euo pipefail` —
  bare, `""`, `agent-7`, a traversal id, a spaced id and a newline id all
  returned cleanly (output in "Checks that passed").

Definition order is fine: `_gitlore_agent_suffix` is defined below its callers,
and bash resolves function names at call time from a fully-sourced file. The
66/0 suite run is the proof, not the reasoning.

## Assessed, no defect — whitespace safety

- Inside both helpers every expansion is inside double quotes:
  `git -C "$1" rev-parse --git-path "gitlore-…$(…"${2:-}")"`. The command
  substitution sits inside the quoted argument, so its result is not re-split.
- Inside `_gitlore_agent_suffix`, `printf '%s' "$1"` is quoted and the result is
  consumed through a quoted `$( )`. No unquoted expansion, no `$IFS` dependence,
  no glob.
- All four existing call sites are whitespace-safe as written and stay so:
  `stash=$(gitlore_index_preimage_file "$mempath")` (`index-sync-pre.sh:40`),
  `stamp=$(… "$mempath")` (`:41`), `stashfile=$(… "$mempath")`
  (`index-sync-post.sh:30`), `stamp=$(… "$mempath")` (`index-compose.sh:32`),
  and `rm -f "$(gitlore_compose_stamp_file "$mempath")"`
  (`add-tier-batch.sh:75`) — assignment from a command substitution, or a quoted
  one, in every case. A gitdir path containing spaces survives all five.
- Residual, unchanged by this slice and inherent to the printing-a-path
  contract: `$( )` strips trailing newlines, so a gitdir path ending in a
  newline would lose it. Every caller in the repo uses `$( )`; nothing here
  makes that worse, and the guard now prevents this slice from *introducing* an
  interior newline into the name.

## Assessed, belongs to a later slice — the stranded-file residual comment

The item requires the residual to be bounded in a comment "the way
`index-sync-post.sh:35-38` already bounds a stale pre-image". It is
**not present yet, and it does not belong here.** The residual is a lifecycle
claim — a subagent dies mid-batch, its keyed file survives, the next batch of
that same agent id consumes and deletes it, and agent ids are not reused — and
the lifecycle lives in the pre/post pair, not in a helper that mints a name. The
model the item names is itself a comment on `index-sync-post.sh`'s `rm -f`.

Its two homes, both owned by later slices:

- `scripts/cc-hooks/index-sync-pre.sh:43-47` — slice 2. That comment is the
  falsified assumption ("an existing one here always belongs to the batch in
  flight") the item already requires rewriting; the bound is the natural
  continuation of the rewrite.
- `scripts/cc-hooks/index-sync-post.sh:35-38` — slice 3, extending the stale
  pre-image bound that is already there to cover the keyed case.

Not added in slice 1. Both files are explicitly out of this dispatch's scope.

## Assessed, no defect — comment accuracy

Checked every comment in `scripts/lib/index-sync.sh` that could have been
falsified by the keying:

- `gitlore_index_preimage_file`'s header — "inside the submodule gitdir
  (untracked; mirrors `gitlore_commit_msg_file`)" still holds; the change moved
  the id into the *name*, not the path root, and `--git-path` still roots it in
  the gitdir. `gitlore_commit_msg_file` still exists
  (`scripts/lib/util.sh:133`). The `$2` sentence was extended to point at
  `_gitlore_agent_suffix` rather than leave "appends `-<agent_id>`" reading as a
  verbatim append.
- `gitlore_compose_stamp_file`'s header — "each PostToolBatch hook consumes and
  deletes its own baseline, so neither depends on running before or after the
  other" is about the sync-vs-compose split, orthogonal to per-agent keying, and
  remains true.
- `gitlore_compose_stamp` (`:140`), `_gitlore_file_stamp`,
  `gitlore_compose_stamp_get` — these are about the stamp's *contents*, not its
  path. Untouched, unaffected.
- `_gitlore_nudge_file` / `_gitlore_nudge_reset` / the budget and upgrade nudge
  wrappers — a separate family of gitdir files keyed by session, not by agent.
  Its `find … -name "gitlore-$kind-nudged-*"` sweep (`:196`) cannot collide with
  `gitlore-index-preimage-*` or `gitlore-compose-stamp-*`. Unaffected.
- The file's own header (`:1-3`) — "No side effects except the one write in the
  setter" still holds; both helpers only print.

No stale comment found elsewhere in the file.

## Discrimination check (in-place mutation)

Saved the SUT, mutated it in place, ran, restored — the tests were never moved
or edited.

- **M1, suffix dropped** (`--git-path gitlore-index-preimage`, both helpers):
  cases 1 and 3 pass, cases 2 and 4 fail on `[ "$output" = "$base-agent-7" ]`
  (lines 638, 657). The suffix contract discriminates.
- **M2, naive unconditional `-${2:-}`**: cases 2 and 4 pass, cases 1 and 3 fail
  on `[ "$output" = "$base" ]` (lines 627, 646). The unsuffixed contract rejects
  the trailing-hyphen implementation.

Restored from the saved copy; `git diff` afterwards shows only this review's
fix, and `git status --short` shows `M scripts/lib/index-sync.sh` alone (the
`??` dotfile entries pre-date the session).

## Checks that passed, by name

- `shellcheck -s bash scripts/lib/index-sync.sh` — exit 0.
- `scripts/lint-shell.sh` — `lint-shell: 137 files clean` (unchanged count; no
  file added or left behind).
- `scripts/run-bats.sh tests/index_sync.bats` — **66 passed, 0 failed**, the
  slice's required figure, after the fix.
- `scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats`
  — 24 passed, 0 failed. Run because these two suites call
  `gitlore_compose_stamp_file memory` (`cc_hook_index_compose.bats:58,81`) and
  exercise `add-tier-batch.sh:75`, the unsuffixed paths the guard must leave
  untouched.
- Live-behaviour probe of both helpers under `set -euo pipefail`, sourced from
  the edited file:

  ```
  bare:    [.git/gitlore-index-preimage]
  empty:   [.git/gitlore-index-preimage]
  agent-7: [.git/gitlore-index-preimage-agent-7]
  stamp7:  [.git/gitlore-compose-stamp-agent-7]
  trav:    [.git/gitlore-index-preimage-_________etc_passwd]
  space:   [.git/gitlore-index-preimage-a_b]
  newline: [.git/gitlore-index-preimage-a_b]
  ```

  — the traversal, the space and the newline are all confined to one name inside
  the gitdir, and the two contract cases are byte-identical to before.
- `${2:+-$2}` / `${2:-}` under `set -u` — probed directly under `bash` and `sh`,
  both exit 0 with the alternative value.
- `git rev-parse --git-path` composition probe on a scratch repo — verbatim
  `<gitdir>/<name>` for the plain, spaced, traversal, absolute and
  newline-bearing names; this is the evidence the guard rests on.
- Mutation harness M1/M2 above.
- `git status --short` / `git diff -- scripts/lib/index-sync.sh` — one file
  modified, no throwaway fixture left in `tests/` or `scripts/`.

## Out of scope, untouched

- `tests/index_sync.bats` — reviewed at RED, not edited.
- `scripts/cc-hooks/index-sync-pre.sh`, `index-sync-post.sh`,
  `index-compose.sh`, `add-tier-batch.sh` and their comments — slices 2–4. Read
  only, to judge what the helpers' output is used for.
- Slices 2–4's test cases; `tests/cc_hook_index_compose.bats` and
  `tests/cc_hook_add_tier.bats` (run, not edited).
- `docs/`, `memory/`, and everything under `plans/` other than this report.

Nothing committed. `just precommit` not run, per the dispatch. Note that
`scripts/lib/index-sync.sh` is a gated input, so the `lint`/`test-unit`/
`test-integration` sentinels recorded for `853de3c` are now stale for this tree;
the orchestrator's commit will need a fresh gate run.
