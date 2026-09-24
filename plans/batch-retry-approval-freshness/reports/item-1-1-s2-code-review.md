# Item 1.1, slice 2 — code review

`scripts/cc-hooks/memory-commit-batch.sh` at `16abc35`. One MAJOR fix, one
MINOR hardening, two comment edits, all applied in place. Nothing committed —
the only tracked change in the tree is that file. The mutation probe the
dispatch specified was run first, against the code as committed.

## Findings

### 1. MAJOR — `absent` is reachable, and it took the re-approval branch

The dispatch's premise was that `absent` cannot occur because the
`[ ! -s "$msgfile" ]` branch exits earlier. It does occur, because the message
file can be consumed *during* the run and the run still fail.

`scripts/lib/resolve-sync-memory.sh:245` removes `$msgfile` immediately after a
successful `git commit`. Three `return 1` arms sit after it, all in the
`HEAD:live` fast-forward block:

- `:267` — the push failed for a reason that is not divergence (a ref lock, a
  corrupt object); git's own words are the message.
- `:275` — divergence classified, `gitlore_yield_merge` itself failed.
- `:285` — divergence classified and a merge was *prepared*; this is the
  `gitlore: memory merge prepared` case the `gitlore:resolve` skill exists for.

On each, `commit-memory.sh` exits 1 with `$msgfile` already gone, the hook's
`else` runs, `gitlore_commit_msg_freshness` answers `absent`, and
`[ "$fresh" = "yes" ]` is false — so the committed code emitted the re-approval
pair. Every clause of it is wrong there:

- it points the agent at `$msgfile` to "present it to the user again", and the
  file does not exist;
- it promises "the commit then completes on its own" after a commit that has
  already landed — memory is clean, so the next batch takes the
  `gitlore_memory_dirty = 0` arm at line 76 and reports "already clean";
- it drops `$out`, which on the `:285` arm is the prepared-merge directive and
  on `:267` is git's own words. That is the only actionable content, and before
  this slice it was emitted.

So the slice regressed the post-commit fast-forward failures, including the
merge-preparation one.

**Fixed** by making the re-approval arm fire on `no` alone. The condition is now
`[ "$fresh" != "no" ]` guarding the deferred arm, which keeps the deferred
message first in reading order and makes the `$out`-carrying arm the default for
any value the function grows later. `absent` therefore lands back on exactly the
message it got before the slice.

Design point 3 names `no` and only `no` ("`no` means something newer than the
approval is in the store … and the hook emits its own message"), so this is the
design as written rather than a departure from it.

Residual, not fixed and out of this slice's scope: on the `absent` path the
deferred `additionalContext` still says "with the approved summary preserved",
which is false once the commit consumed it. That wording predates the slice and
is unchanged by it. It wants either its own arm or a softened clause; worth a
follow-up item, not a silent edit here.

### 2. MINOR — an unreadable freshness could have killed the hook mid-emit

The dispatch asked whether `fresh=$(gitlore_commit_msg_freshness "$mempath")`
can abort the hook under `set -euo pipefail`. Probed, not reasoned:

- A failure *inside* the function cannot. Bash clears `-e` in
  command-substitution subshells when not in posix mode, so `m=$(stat …)` on a
  file that vanished between `find` and `stat` (util.sh:298) prints to stderr
  and the loop carries on. Verified both ways: `set -e; f(){ false; echo in-f; };
  z=$(f)` exits 0 under `bash`, 1 under `bash --posix`.
- A failure on the function's *last* command would. `z=$(f)` where `f` ends
  `return 1` aborts the outer shell at exit 1, emitting nothing. Every exit path
  of `gitlore_commit_msg_freshness` ends in `printf 'absent'`, `return 0` or the
  `awk`, and its one `|| return 1` guards `gitlore_commit_msg_file`, which is a
  bare `printf` — so the abort is not reachable today.

Not reachable is not the same as defended, and the failure mode is the silent
one: a hook that dies emits no JSON, the agent is told nothing about a commit it
asked for, and only the user sees a stderr line. **Hardened** with
`|| fresh=absent`, the same idiom line 116 already uses for `memhead`. With
finding 1 applied, that default degrades to the arm carrying `$out` rather than
to nothing.

### 3. TRIVIAL — a header claim the file contradicts six lines later

Line 14 read "The trigger file IS the signal, so the batch payload is unused",
while lines 20-22 read `cwd` out of the payload for the stranded-trigger check
and say so. Pre-existing, in scope as the file-as-committed, one word wide.
**Fixed**: "The trigger file IS the signal; the batch payload carries no
request." The constraint survives, the false claim goes.

### 4. The comment block above the run — narration cut

Kept, per the skill's code-comment bar: the bare run, both IPC files kept on
failure, which message each freshness value selects, and D16. Cut: "the same
freshness question, asked again", "rather than relied on as-is", "no longer
reads as covered", and the `(mtime against the newest file in the store)`
parenthetical — that rule is stated at its own function and in
`docs/references/git-hooks.md`, and a second copy here is what drifts.

Added, because finding 1 makes it a constraint a maintainer needs in order not
to re-break this: why `absent` belongs with `yes` rather than with `no`. That is
rationale for not breaking the code, which the skill's cut explicitly keeps.

### 5. Checked, no defect

- **The directive text.** Acts only: present it again as a blockquote, amended
  for what changed, write it to `$msgfile`. One reassurance clause ("the commit
  then completes on its own"), matching the no-summary branch at line 94 and
  true of the flow. No mechanism — freshness, mtime and the retry are all
  absent. The trigger is not named, so the "withhold, don't forbid" test passes
  without the no-summary branch's explicit "do not re-trigger it": the agent has
  no identifier here to re-trigger with. `$msgfile` twice is two acts — read the
  summary there, write the approved one there.
- **The `systemMessage`.** Byte-compared against `design.md:65`: identical.
  Lowercase, em-dash separator, one line, factual, no imperative. It carries no
  clause and no `$out`, which is what pins "the script's reason is dropped on
  this branch".
- **`.claude/rules/shell.md`.** No `2>/dev/null` added; every expansion quoted
  (`"$mempath"`, `"$msgfile"`, `"$fresh"`, `"$clause"`); no `read` loop and no
  whitespace splitting introduced; `printf '%s\n\n%s\n'` with quoted operands,
  and `emit` builds the JSON with `jq --arg`, so the newlines survive.
- **shellcheck.** `just lint` → `lint-shell: 210 files clean`.
- **400-line cap.** `wc -l` = 133.
- **The `yes` arm is untouched**, so the locked-repo and fix-needed tests keep
  their exact prior text.

## Mutation result

`touch "$msgfile"` inserted in the stale branch immediately before `emit`, run
against the code as committed:

```
not ok 8 a fix after an aborting index does not commit under the old approval
# (in test file tests/cc_hook_memory_commit_batch.bats, line 206)
#   `[ ! "$msgfile" -nt "$TMP_REPO/before-second-batch" ]' failed

bats: 11 passed, 1 failed
```

Red on the `-nt` guard, which is the assertion the test review added for exactly
this mutation — not on the HEAD check and not on `cmp`. The edit was inverted
and `git diff` confirmed empty before the fixes went in; `bash
scripts/run-bats.sh tests/cc_hook_memory_commit_batch.bats` → 12 passed, 0
failed.

## Runs after the fixes

- `bash scripts/run-bats.sh tests/cc_hook_memory_commit_batch.bats` — 12 passed,
  0 failed.
- `bash scripts/run-bats.sh tests/commit_memory.bats` — 19 passed, 0 failed
  (slice 1's bare-mode suite, since finding 1 turns on what `commit-memory.sh`
  leaves behind).
- `bash scripts/run-bats.sh tests/commit_memory_retry.bats
  tests/index_sync_propagation.bats tests/plugin_distribution.bats` — 42 passed,
  0 failed. Those are the other three suites naming `memory-commit-batch`.
- `just lint` — `lint-shell: 210 files clean`.

`just precommit` was not run: the dispatch scopes this to review and forbids
committing, and the full gate belongs to whoever lands the fix.

## In-scope but unfixable here

- **No test covers the `absent` path.** Finding 1 is a real regression that the
  suite could not see, and the fix is currently unguarded — a later edit back to
  `= "yes"` would pass all 12. The test wants a fixture where `commit-memory.sh`
  commits and then fails the `HEAD:live` fast-forward (a diverged local `live`
  is the reachable shape), asserting the deferred message with `Reason:` rather
  than the re-approval pair. Tests are scoped OUT of this dispatch, so it is
  named here rather than written.
- **The "approved summary preserved" clause on the `absent` path**, per the
  residual in finding 1 — it needs either a third arm or a softened clause, and
  either is a design change rather than a review fix.
