# Item 1.1, slice 1 — code review

`scripts/commit-memory.sh` as committed in `4dd02bc`. Two fixes applied, both
in that file. Nothing committed; the only tracked change in the tree is
`scripts/commit-memory.sh`.

## Findings

### 1. MAJOR — the guard was `-e`, and an empty approval file is not an approval

`elif [ ! -e "$msgfile" ]` admits a file that exists and is empty. Nothing
downstream screens it: `gitlore_commit_msg_freshness`
(`scripts/lib/util.sh:290`) tests `[ -f "$msgfile" ]` and then compares mtimes,
so an empty file freshly written reads `yes`, and
`gitlore_sync_memory_to_live` runs the whole commit path on it —
`gitlore_compose` writes carriers into the store, tiers are synced — before
reaching `git commit -q -F "$msgfile"`
(`scripts/lib/resolve-sync-memory.sh:243`).

Verified empirically rather than by reading, with a scratch bats file over the
suite's own `make_parent_with_memory` fixture (dirty memory, `: > "$msgfile"`),
deleted after the run. Against the committed script:

```
STATUS: 1
ERR: Aborting commit due to empty commit message.
HEAD moved: no
msgfile exists: yes   size: 0
freshness after: yes
dirty after: 1
```

Three things are wrong with that. The message is git's raw text with no
`gitlore:` prefix, no agent/user arm and no remedy. The `|| { touch "$msgfile";
return 1; }` arm on that commit restamps the empty file, so freshness stays
`yes` and every retry reproduces the identical error — a loop, not a one-off.
And it is a regression against the pre-slice behaviour: bare with an empty file
used to refuse with the "needs an approved summary" directive, because bare
refused unconditionally.

The sync's own handling does not make `-e` right; it has no empty-file case at
all. Fixed by narrowing the guard to `-s`:

```
  elif [ ! -s "$msgfile" ]; then
    # -s, not -e: an empty file carries no approval, and passing it on reaches
    # `git commit -F` with an empty message, whose abort restamps the file.
```

Re-probed after the fix over the same fixture: status 1, stderr
`gitlore: memory is dirty; commit-memory needs an approved summary. Pass it
with -m <summary> or -F - (heredoc).`, memory still dirty.

`-s` is also what the block's own comment already describes — "refusing up
front only when there is none to judge" is false for an empty file under `-e`
and true under `-s`. It is consistent with the hook in slice 2, whose
`[ ! -s "$msgfile" ]` branch screens absent-or-empty ahead of the run, so the
hook path is unaffected and the script's notion of "no summary" now matches the
hook's.

The design's wording ("keeps refusing when no message file exists") and the
dispatch interface line ("when no approval file exists") both read as `-e` on
their face. `-s` is the behaviour they intend — an empty file is the absence of
an approval, not a stale one — and nothing in either is contradicted.

### 2. MINOR — misaligned continuation in the usage header

The bare form's second header line put its `#` at column 42 where the other
three usage lines carry theirs at column 41. Fixed by removing the extra space;
the usage block now aligns.

### 3. Checked, no defect

- **`.claude/rules/shell.md`.** Every path is quoted (`"$msgfile"`,
  `"$(dirname "$msgfile")"`, `"$mempath"`); no splitting, no `ls`/`awk`
  parsing. No `2>/dev/null` added. No `read` loop. Under `set -e`,
  `msgfile=$(gitlore_commit_msg_file "$mempath")` is a plain assignment, so a
  failure of that helper aborts rather than yielding an empty path — the
  hoisting of the assignment above the branch did not introduce an unchecked
  status.
- **Hoisting `msgfile` out of the `-m`/`-F` arm.** It is now computed on the
  refusal path too, which is what the `-s` test needs. No side effect:
  `gitlore_commit_msg_file` only prints.
- **`mkdir -p` placement.** It stays inside the `have_summary` arm, which is
  the only one that writes. The bare arm does not create `.claude/`, correctly
  — a bare call in a tree with no `.claude/` refuses rather than materialising
  a directory it will not use.
- **Clean memory.** Unchanged: the whole block is inside
  `gitlore_memory_dirty = 1`, so bare on clean memory still falls straight to
  `gitlore_sync_memory_to_live` for the HEAD-vs-live fast-forward.
- **"by construction" in the block comment.** Kept. It is not the fourth
  instance of a tic here; it names why the `-m`/`-F` path needs no freshness
  check of its own — the write's recency *is* the satisfaction — which is the
  constraint that stops a maintainer moving the write earlier. The parenthetical
  "(written immediately before the commit)" is what carries it. The rest of the
  block states the asymmetry between the two arms and no mechanism a reader
  would narrate back; no narration cut applies.
- **`exit $?` on the last line.** Dead under `set -e` (the function's non-zero
  return terminates the script with that status first), but pre-existing and
  untouched by this slice.
- **shellcheck.** `just lint` after both edits → `lint-shell: 210 files clean`.

## Mutation check

Mutation applied in place, as directed: an `else` arm after the `elif`, running
`printf '%s\n' "$(cat "$msgfile")" > "$msgfile"` on the bare path — the rewrite
that mints a fresh approval, i.e. the defect this slice closes.

`bash scripts/run-bats.sh tests/commit_memory.bats`, foreground:

```
not ok 7 bare invocation refuses a stale approval file and leaves it
# (in test file tests/commit_memory.bats, line 95)
#   `[ "$status" -eq 1 ]' failed

bats: 17 passed, 1 failed
```

The mutation is caught, and only by the intended test. It reds one assertion
*earlier* than the dispatch predicted — not on the restamp guard but on
`[ "$status" -eq 1 ]`, because the rewrite makes the approval fresh and the
commit then succeeds, so the bare run exits 0. That is a stronger red, not a
weaker one: the test discriminates at its first assertion.

Consequence worth recording: no mutation of this script isolates the restamp
guard `[ ! "$msgfile" -nt "$TMP_REPO/before-run" ]`, because any restamp on the
bare path also makes the file fresh and flips the status. The guard would fire
only for a change that restamps while still refusing, which this entry point has
no arm for. It is belt-and-braces rather than vacuous; the discriminating
assertions are the status and the `cmp -s` content compare. No change made —
the tests are out of scope for this review.

Mutation reverted by restoring the saved copy. Re-run:
`bats: 18 passed, 0 failed`.

## Flagged, not fixed

- **No test covers the empty approval file.** Finding 1 is a real behaviour
  change with no assertion behind it; `tests/commit_memory.bats` pins absent and
  present-fresh and present-stale, not present-empty. Tests are out of scope for
  this review, so nothing was added. A third bare-mode case — empty `$msgfile`,
  dirty memory, expect status 1, the `Pass it with -m` wording, memory still
  dirty and `HEAD` unmoved — belongs in that file. It reds against the committed
  `-e` (stderr is git's `Aborting commit due to empty commit message.`) and
  greens against the `-s` fix, so it is evidence rather than decoration.
