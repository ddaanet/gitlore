# Phase 1 checkpoint review — corrector

Reviewed:
`git diff 3502a86..HEAD -- scripts/lib/resolve.sh tests/merge_memory.bats`
against runbook Phase 1 (Items 1.1, 1.2) and the outline.

## Verdict

The implementation matches the spec. No production-code defects were found. One
major test gap (a regression Item 1.2 caused) and two minor points are fixed in
`tests/merge_memory.bats`. `scripts/lib/resolve.sh` is unchanged.

## Spec conformance (checked, no finding)

- **Full refusal passed through.** `gitlore_adopt_tier_into_root` passes
  `$composed` as the seventh argument.
- **Unrepairable arm.** It prints the carrier lines as `live:MEMORY.md:`, then
  the lines `gitlore_compose_problems_in "$tierpath/MEMORY.md"` does not select,
  under the `could not take <label>'s lines:` header with the `gitlore:   `
  prefix. When such lines exist, the remedy is the two-fix string. Otherwise the
  remedy is unchanged. Prefixless problem lines count as "other", as the spec
  defines it.
- **Transient arms.** mktemp, arrival read, pin read, rewrite, commit build,
  `live` advance and checkout follow each print their own line, then call
  `gitlore_adopt_report_refusal_and_walk_back` with `$composed` and
  `Run /gitlore:merge again.`. The three read/rewrite/build arms share the
  `[ -z "$repair" ]` call. Checkout follow passes `the repair`.
- **Walk-back wording.** `its local 'live' keeps <live_holds>.` defaults to
  `what arrived`. The retry-refusal call passes `""` and `the repair`, so it
  keeps "Fix the store, …". The report helper forwards both optional arguments.
  The signatures match **Interfaces**.
- **Item 1.2.** `mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"` is in place.
  The `rev-parse --absolute-git-dir` lookup and the `gitdir` local are gone. The
  comment says "outside the repository". The mktemp arm's line matches the spec.
- **Scratch hygiene.** The scratch directory is removed on every path. The
  mktemp failure creates none. The unrepairable arm removes it before walking
  back. Every other arm reaches the shared `rm -rf` before returning.
- **Whitespace and bash 3.2.** All expansions are quoted. `read` carries
  `|| [ -n "$line" ]`. No bash-4 constructs.

## Findings

### 1. Major — scratch cleanup is untested since the scratch moved to `$TMPDIR` (FIXED)

The repair tests guarded cleanup with `tier_gitdir_files` before/after equality.
That check still guards "nothing written into the gitdir", but after Item 1.2 it
no longer sees the scratch directory. A mutant that replaces both
`rm -rf -- "$scratch"` lines with `:` passed all 15 repair tests
(`--filter 'repair|cannot fix'`: 15 passed, 0 failed). It leaked 13
`/tmp/gitlore-repair.*` directories. I removed them by explicit name.

Fix: a `repair_scratch_dirs <dir>` helper next to `tier_gitdir_files`, which
lists `gitlore-repair.*` directly under the directory. Four tests now run the
command with `TMPDIR` set to a fresh `$BATS_TEST_TMPDIR/tmp` and assert that
nothing is left there:

- adoption:
  `a take repairs a duplicate pointer that arrived and adopts the repair`;
- the unrepairable arm's early return:
  `an arrival the repair cannot fix walks back and names upstream`;
- a transient arm after the shared `rm`:
  `a repair whose commit build fails walks back and points upstream`;
- `a repair's scratch directory lives under TMPDIR, not the tier's gitdir`.

The last test's existing `seen` count already proves that `TMPDIR=… run` reaches
the command.

Against the same mutant, all four red on the new assertion:

```
not ok 1 a take repairs a duplicate pointer that arrived and adopts the repair
#   `[ -z "$(repair_scratch_dirs "$tmp_env")" ]' failed
not ok 2 a repair whose commit build fails walks back and points upstream
#   `[ -z "$(repair_scratch_dirs "$tmp_env")" ]' failed
not ok 3 a repair's scratch directory lives under TMPDIR, not the tier's gitdir
#   `[ -z "$(repair_scratch_dirs "$tmp_env")" ]' failed
not ok 4 an arrival the repair cannot fix walks back and names upstream
#   `[ -z "$(repair_scratch_dirs "$tmp_env")" ]' failed
bats: 0 passed, 4 failed
```

`resolve.sh` was restored with `git checkout --`, and `git status` shows
`scripts/` clean.

### 2. Minor — transient-arm tests do not pin the walk-back wording (FIXED)

The commit-build, mktemp and `live`-advance tests matched
`Run /gitlore:merge again.` anywhere in stderr. None of them checked the
walk-back sentence it closes. The `live`-advance test is even named "keeps the
arrival" and asserts only the ref. All three now assert
`its local 'live' keeps what arrived. Run /gitlore:merge again.`. This covers
the `live_holds` default on the transient arms. The checkout-follow test already
asserted the joined `keeps the repair.` form.

### 3. Minor — retry-refused test used `run ! grep` for a negative match (FIXED)

`run ! grep -qF 'keeps what arrived' <<<"$stderr"` overwrote `$status` and
`$output` in the middle of the assertions. It is now
`[[ "$stderr" != *"keeps what arrived"* ]]`, the form its sibling tests use.

### Reviewed, no change

- **Item 1.2 slice 2's `mktemp` stub.** It matches `*gitlore-repair.*`, so
  `gitlore_git`'s own mktemp calls pass through. The `mktemp-hit` premise shows
  that the repair's call was the one refused.
- **Item 1.2 slice 1's `ls -d … 2>/dev/null`** in the stub. One glob is expected
  to miss, and the inline comment says so.
- **The unrepairable arm filters line by line** through
  `gitlore_compose_problems_in`, one subshell per line. That is acceptable for
  refusal-sized input, and it keeps a single definition of "names the carrier".
- **Out of scope as briefed:** the walk-back's own checkout-failure branch
  always says "fix the store".

## Guard slice 1.1/5 mutant run

Mutant: in the `live`-advance arm, replace the
`gitlore_adopt_report_refusal_and_walk_back … "Run /gitlore:merge again."` call
with `gitlore_adopt_walk_back_tier "$mempath" "$tier" "$old_gitlink" "$label"`.
The test is
`a repair whose live advance fails walks back and keeps the arrival`.

```
not ok 1 a repair whose live advance fails walks back and keeps the arrival
# (in test file tests/merge_memory.bats, line 798)
#   `[[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"$'\n'"gitlore:   memory/ddaanet/MEMORY.md: duplicate pointer path a.md"* ]]' failed
bats: 0 passed, 1 failed
```

It reds on the refusal-header assertion. With finding 2 applied, the joined
`keeps what arrived. Run /gitlore:merge again.` assertion would also catch the
mutant's "Fix the store" remedy. `resolve.sh` was restored with
`git checkout --`, and `git status --short scripts` is empty.

## Result after fixes

- `shellcheck tests/merge_memory.bats`: clean.
- `scripts/run-bats.sh tests/merge_memory.bats`: `bats: 41 passed, 0 failed`.
- No `/tmp/gitlore-repair.*` is left behind.
- Working tree: only `tests/merge_memory.bats` is modified, plus this report.

## UNFIXABLE

None.
