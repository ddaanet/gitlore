# Item 1.1, slice 1 — test review

`tests/commit_memory.bats`, the two new bare-mode tests. Reviewed, three fixes
applied, still red on their assertions. Nothing committed; the only tracked
change in the tree is `tests/commit_memory.bats`.

## Mechanical check

`bash scripts/run-bats.sh tests/commit_memory.bats`, foreground, before any
edit: **16 passed, 2 failed**. Both failures are assertion failures, not a
missing command and not a bats error.

- `bare invocation commits on a fresh approval file and consumes it` — FAILED
  on `[ "$status" -eq 0 ]`, the first assertion after `run`.
- `bare invocation refuses a stale approval file and leaves it` — FAILED on
  `[[ "${output}${stderr}" == *"no approved commit summary"* ]]`, the
  discriminating wording assertion. `[ "$status" -eq 1 ]` ahead of it passes
  today, as the RED report states.

Neither PASSED, neither errored. This reproduces the RED report exactly.

## Findings

### 1. CRITICAL — the stale test's `-m` negative was unsatisfiable

`[[ "${output}${stderr}" != *"-m"* ]]` can never hold once GREEN routes the
bare invocation to the sync's refusal: that refusal ends with `… write it to
$msgfile, then retry.`, and the msgfile basename is
`gitlore-memory-message`, whose `-memory-` contains `-m`. The test would have
stayed red through a correct implementation, and the GREEN driver would have
had no way to satisfy it.

Verified empirically rather than by reading: a scratch bats file drove
`gitlore_sync_memory_to_live` (via the suite's own `write_sync_driver`) over
this exact fixture — dirty memory, approval backdated to `200001010000` — and
printed the captured output. It contains `-m` (`CONTAINS -m: yes`) and does not
contain the usage-era wording (`CONTAINS usage-era: no`). The probe file was
deleted after the run.

Fixed by narrowing the negative to the usage-era refusal's own operand
phrase, which keeps the discriminator the dispatch asked for and is
satisfiable:

```
  # The usage-era refusal's own operand, and not a bare `-m`: the sync's refusal
  # names $msgfile, whose basename `gitlore-memory-message` contains `-m`.
  [[ "${output}${stderr}" != *"Pass it with -m"* ]]
```

`scripts/commit-memory.sh:57` emits `… Pass it with -m <summary> or -F -
(heredoc).`, so the negative still fires if GREEN leaves the bare path on the
usage-era branch. It stays paired with the positive on `no approved commit
summary` over the same fixture and the same run.

### 2. MAJOR — the fresh test could be satisfied vacuously

`[ -z "$(git -C memory status --porcelain)" ]` plus `wt = live` is also what
*discarding* the edit leaves: a GREEN that ran `git checkout` over the dirty
tree and removed the approval file passed every assertion. Nothing tied the
commit to the approval file's contents either.

Added a `head_before` capture and two assertions — HEAD moved, and the commit
subject is the approval file's own text:

```
  [ "$wt" != "$head_before" ]
  [ "$wt" = "$live" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes" ]
```

The capture sits before `run`, so the first failing assertion today is still
`[ "$status" -eq 0 ]`.

### 3. MAJOR — the stale test checked content but not the restamp

`[ "$(cat "$msgfile")" = "$content_before" ]` compares through command
substitution, which strips trailing newlines on both sides, and says nothing
about mtime. A rewrite of the file with identical bytes is exactly the defect
this slice closes — it mints a fresh approval — and that rewrite passed the
assertion.

Replaced with a byte-exact compare and an mtime guard, using the marker idiom
the suite already carries (`tests/commit_memory.bats`, the rc-1 restamp test):

```
  cp "$msgfile" "$BATS_TEST_TMPDIR/approval.before"
  …
  : > "$TMP_REPO/before-run"
  sleep 1
  …
  cmp -s "$msgfile" "$BATS_TEST_TMPDIR/approval.before"
  [ ! "$msgfile" -nt "$TMP_REPO/before-run" ]
```

The `sleep 1` is what makes the guard meaningful on a one-second-granularity
filesystem: without it a restamp inside the marker's own second would not
register as newer. Satisfiable by GREEN — the `fresh != yes` branch of
`gitlore_sync_memory_to_live` (`scripts/lib/resolve-sync-memory.sh:32-55`)
returns before any restamp arm, so it neither rewrites nor touches the file.

### 4. Checked, no defect

- **Stale fixture ordering.** `touch -t 200001010000` is applied after the file
  is written, and the freshness scan
  (`gitlore_commit_msg_freshness`, `scripts/lib/util.sh:290`) walks
  `find "$mempath" -type f`, which the approval file sits outside of. The
  approval is strictly older than `memory/notes.md`, so the `>=` compare
  answers `no`. BSD-portable.
- **Fresh fixture ordering.** The approval is written after the memory edit and
  the compare is `>=`, so a same-second write still reads `yes`.
- **Whitespace.** Every path is quoted; no splitting, no `ls`/`awk` parsing.
  `$TMP_REPO` comes from `mktemp -d` under `$TMPDIR`.
- **`.claude/rules/shell.md`.** No `2>/dev/null`, no bare top-level `!`, no
  unguarded `read` loop. `CLAUDECODE=1 run --separate-stderr` matches the form
  the suite's other agent-arm tests use.
- **shellcheck.** `just lint` → `lint-shell: 210 files clean`.

## Final red run

`bash scripts/run-bats.sh tests/commit_memory.bats` after the fixes:

```
not ok 6 bare invocation commits on a fresh approval file and consumes it
# (in test file tests/commit_memory.bats, line 64)
#   `[ "$status" -eq 0 ]' failed
not ok 7 bare invocation refuses a stale approval file and leaves it
# (in test file tests/commit_memory.bats, line 96)
#   `[[ "${output}${stderr}" == *"no approved commit summary"* ]]' failed

bats: 16 passed, 2 failed
```

Both still fail on the intended assertion, and the pre-existing 16 still pass.
