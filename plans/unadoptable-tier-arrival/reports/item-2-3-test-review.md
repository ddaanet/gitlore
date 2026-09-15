# Item 2.3 test review

Verdict: tests fit for GREEN after the fixes below. `scripts/` untouched at exit
(`cmp` against a saved copy after every mutation,
`git status --porcelain scripts/` empty). `shellcheck` clean on both `.bats`
files.

## Mechanical results (re-run by the reviewer, after fixes)

| Slice | Test | Current code | Mutation |
| --- | --- | --- | --- |
| 1 | push: "a repair taken inside a push is published before memory records it" | pass | red, see below |
| 2 | push: "a repair taken by the behind arm is published before memory records it" | red `push_behind_vs_diverged.bats:390` `[ "$(cat "$hookfile")" = "$R" ]` | — |
| 3 | merge: "a take fetches first and takes a repair another consumer published" | red `merge_memory.bats:897` `[ "$status" -eq 0 ]` | — |
| 4 | merge: "a failed fetch still adopts local live and reports the fetch failure" | pass | red `merge_memory.bats:926` HEAD = stranded |

Slice 2's red reason confirmed, not inferred: a throwaway copy of the file
replaced the hook assertion with `= "$remote_sha" && skip`; it skipped, so the
hook fired once and saw the unrepaired arrival on the tier remote.

## Wrong-reason hunting

**Slice 1.** The RED driver's mutation (removing the live-ahead adoption) reds
on exit status only. The mutation asked for — keep the repair, skip publishing
the tier before memory's push — was applied as
`gitlore_merge_stores "$mempath" || return 1; continue` in the live-ahead branch
of `gitlore_push_stores`. It reds on the hook snapshot
(`push_behind_vs_diverged.bats:366`, `[ "$(cat "$hookfile")" = "$R" ]`), so
slice 1 pins the publish order and not just the end state.

**Slice 3.** `status -eq 0` is the first failing line, but the later assertions
are specific. A green that exits 0 after repairing its own stale copy would
leave tier HEAD at a local sibling of R', not at `$fixed_sha`, and the
`repaired` absence check catches it on output too.

**Satisfiability.** A rough sketch of the Item 2.3 change (fetch before
adoption, adopt on a failed fetch or unless `live` is an ancestor of
`origin/live`, behind arm pushes `live` when strictly ahead) turned all four
tests green: 2/2 in each file. So no assertion demands more than the runbook
does. The sketch was reverted and checked with `cmp`.

**Hook.** It unsets `GIT_DIR`, `GIT_OBJECT_DIRECTORY`,
`GIT_ALTERNATE_OBJECT_DIRECTORIES` and `GIT_QUARANTINE_PATH`. Both tests assert
`[ -s "$hookfile" ]` before reading it. Interpolated paths are double-quoted
inside the generated hook.

**Fixtures and other checks.** Slice 1 uses the `:268` setup plus the
seed/strand duplicate. Slice 2 uses the `:234` setup with a doubled line. Slice
3 uses the `:331` setup with a raw `fetch origin live:live` and a test-local
clone that pushes R'. Slice 4 uses the `:518` setup with the URL set to
`missing.git`. No bare `! cmd` and no multi-line grep. No test holds a ref or
index lock, so none needs `GITLORE_GIT_RETRY_SCHEDULE=0`.

## Fixes applied

1. **Memory's remote was never checked** (slices 1 and 2). The runbook says
   "memory's remote records gitlink R". The tests only read local
   `memory HEAD:ddaanet`. Added
   `[ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live:ddaanet)" = "$R" ]`.
2. **The hook overwrote its file** (`>`). A green that pushed memory once before
   publishing the tier and again after would leave only the second, correct
   snapshot. The hook now appends (`>>`), and the exact-equality check then
   requires one memory push that saw R. The helper comment says why.
3. **Slice 1 did not prove R is the repair of the stranded commit**: it had only
   `R != stranded`. Replaced with `rev-list --parents -n 1 "$R"` =
   `"$R $stranded"`.
4. **Slice 3 had no premise that the other consumer's fix is what the test
   thinks.** Added three checks: the tier remote's `live` is `$fixed_sha`, its
   parent is the arrival `$remote_sha`, and its `MEMORY.md` carries the line
   exactly once.
5. **Plan citations in test source.** The constraints forbid citing plans or
   runbook items. Removed `K6` from the section header and both comments, and
   `item 2.2's` from slice 1's comment. The wording now states the behaviour.

## Not changed

- Slice 4's `grep -q 'ddaanet/local.md' memory/MEMORY.md` matches the `:518`
  test's own assertion for the same state.
- Slice 3's other-consumer clone uses `mktemp -d "${TMPDIR:-/tmp}/…"` then
  `rm -rf`, the same as `push_tier_fact`.
