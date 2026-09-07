# Item 1.1 slice 2 — GREEN (mutation evidence in place of RED)

Commit: `502703c6492a4979101b74f176f1fdf7b84120e5`
`✅ Item 1.1/2 — Dirty-only scope — a clean store is not composed`

## Why no RED phase

Slice 1 already placed the compose call inside `gitlore_sync_memory_to_live`'s
`dirty = 1` branch (`f6ef928`, kept as-is by the code-review fix `84b5132`).
Slice 2 pins exactly that guard, so both new cases pass the moment they are
written against the committed SUT — a RED phase here would be vacuous, per
[[genuine-red-not-missing-sut]]. The dispatch's instructed substitute: write the
tests, then prove they are non-vacuous by mutating the SUT in place and watching
the negative red.

## Tests added

`tests/git_hook_pre_commit.bats`:

- A shared fixture builder, `committed_stale_carrier_store`, used by both cases
  below. It seeds the slice-1 root/carrier divergence, commits it on **both**
  sides (the tier's own history, then memory's) — `seed_tier_bullet` only edits
  the tier's working tree, so without a commit inside `memory/ddaanet` itself
  that submodule stays "modified content" forever and `commit_memory_state`
  alone cannot make the store clean (`git -C memory add -A` records a moved
  submodule HEAD, it does not commit inside it). It then forces
  `git -C memory branch -f live HEAD~1` so HEAD sits one commit past `live` with
  a clean tree — the shape needed to skip `gitlore_sync_memory_to_live`'s
  clean-and-at-live early return (`scripts/lib/resolve.sh`) without ever
  entering the `dirty = 1` branch, which is the guard under test.
- `a clean store is not composed by the commit path` — runs `bash "$HOOK"` over
  that fixture; asserts exit 0, `gitlore_memory_dirty memory` still `0`,
  `git -C memory rev-parse HEAD` unchanged, and the tier carrier's bullet block
  still exactly `- [shared](shared.md) — stale hook`.
- `the same store, made dirty, IS composed` — its own test body (never appended
  to the negative, since a bats body runs under errexit). Same fixture, plus one
  uncommitted `memory/local.md` fact and a fresh approved summary, which flips
  only the guard's trigger input (dirty 0 → 1) without touching the tier side.
  Asserts the committed carrier now reads `- [shared](shared.md) — fresh hook`.

Both pass against the unmodified SUT:
`scripts/run-bats.sh tests/git_hook_pre_commit.bats` → 16 passed, 0 failed.

## Mutation run (this slice's red evidence)

`scripts/lib/resolve.sh` mutated in place: the
`gitlore_compose "$mempath" >/dev/null || true` call hoisted out of the
`if [ "$dirty" = "1" ]; then` block to run unconditionally right after the
clean-and-at-live early return (leaving the per-tier stale-merge guard loop
where it was, and removing only the original call site inside the dirty branch —
no other line touched).

`scripts/run-bats.sh tests/git_hook_pre_commit.bats` against the mutant:

```
not ok 14 the parent pre-commit hook composes the carrier before committing
# (in test file tests/git_hook_pre_commit.bats, line 240)
#   `bash "$HOOK"' failed
# gitlore: memory is dirty and has no approved commit summary. Prepare a summary and present it to the user as a markdown blockquote (`> …`), not a code fence, for confirmation; treat only a clear, un-negated affirmative as approval (a hedge, a question, or any negation is a rejection). Only once approved, write it to /tmp/claude-1000/gitlore-test.DkZ0gf/.claude/gitlore-memory-message, then retry.
[... approval-clause body omitted, unchanged from the hook's own text ...]
not ok 15 a clean store is not composed by the commit path
# (in test file tests/git_hook_pre_commit.bats, line 284)
#   `[ "$(gitlore_memory_dirty memory)" = "0" ]' failed

bats: 14 passed, 2 failed — full log: /tmp/claude-1000/gitlore-bats.M0FsyH
```

The **negative** case (test 15) reds on
`[ "$(gitlore_memory_dirty memory)" = "0" ]` — the discriminating dirty-state
assertion named in the dispatch, exactly as expected: composing unconditionally
rewrites the carrier and the store goes dirty. The **positive** case (test 16,
`the same store, made dirty, IS composed`) stayed green under the mutation, as
its control role requires.

Slice 1's own pre-existing case (test 14) also reds under this mutation, as a
side effect: compose now runs ahead of `gitlore_commit_msg_freshness` inside the
same function, so the freshness check reads mtimes composition just touched and
reports the approved summary stale. This is collateral from the mutation's
placement (deliberately crude — hoisted above the whole `dirty` conditional, not
just reordered within it), not a defect in slice 2's own cases; it is left
unaddressed per the dispatch's scope.

`scripts/lib/resolve.sh` restored: `git checkout -- scripts/lib/resolve.sh`,
confirmed byte-identical to HEAD by `diff` against a pre-mutation copy.
`git diff --stat -- scripts/lib/resolve.sh` empty. Both new cases re-run against
the restored SUT: 16 passed, 0 failed.

## Precommit gate

`just precommit` was launched with `run_in_background: true` first. Its output
stalled after the `lint` step for several minutes with no completion
notification and (from a fresh `Bash` call) no visible `just`/`bats` process —
which first read as the process having died (this box's known OOM fragility
under parallel test jobs). That reading was wrong: a fresh `Bash` invocation
cannot see another background task's processes via `ps` at all (confirmed after
the fact — each call gets its own process-tree view), and `scripts/run-bats.sh`
redirects all `bats` output to a log file, only printing once the whole suite
finishes, so a suite genuinely in progress produces no incremental stdout.
`TaskStop` on that task returned "Successfully stopped", proving it was in fact
still running.

Rather than restart the same background precommit as a lump, the situation was
converged onto this session's own documented fallback (running the gated recipes
separately and sequentially, since the box will not take two suites at once):
`lint`'s sentinel was already fresh from the killed run (it completes before
`test`, so its pass was not lost), and `test-integration` then `test-unit` were
run one at a time as separate background calls, each waited out to its own
completion notification rather than polled via `ps`.

- `just test-integration` → `bats: 72 passed, 0 failed`.
- `just test-unit` → `bats: 778 passed, 0 failed`.

Gate sentinels under `.git/gitlore/gates/`, all postdating the last edit to any
gated input (`tests/git_hook_pre_commit.bats`, 15:40:34): `check-distribution`
15:02 (pre-existing, cached — unaffected by this slice's inputs), `lint` 15:44,
`test-integration` 15:54, `test-unit` 15:58.

## Commit hygiene

Staged and committed only `tests/git_hook_pre_commit.bats`, via
`git commit -m "..." -- tests/git_hook_pre_commit.bats`. No `--no-verify`; the
`commit-msg` hook rewrote the `test:` prefix to the emoji shown above.
`git status --short` after the commit is empty.

## Not touched

`scripts/lib/resolve.sh` (mutated only as the temporary probe described above,
then restored and confirmed byte-identical), slice 3's `case` over
`gitlore_compose`'s return code, every pre-existing case in either suite,
`docs/`, Phases 2 through 4.
