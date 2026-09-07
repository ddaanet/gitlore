# Item 1.1 slice 1 — RED

Both tests exist, both fail on their assertion against unchanged `scripts/`.
Nothing committed; the two test files are the only working-tree changes.

## Files touched

- `/Users/david/code/gitlore/tests/commit_memory.bats`
- `/Users/david/code/gitlore/tests/git_hook_pre_commit.bats`

Each gained `load helpers/tier-fixtures` beside the existing three loads, and
one new `@test`. Neither gained a `source .../index-compose.sh` — see the
deviation note below.

## Test 1 — `commit-memory composes the carrier into the commit it makes`

`tests/commit_memory.bats`. Run: `scripts/run-bats.sh tests/commit_memory.bats`.

```
not ok 10 commit-memory composes the carrier into the commit it makes
# (from function `assert_bullets' in file tests/helpers/tier-fixtures.bash, line 173,
#  in test file tests/commit_memory.bats, line 130)
#   `assert_bullets "$BATS_TEST_TMPDIR/carrier.md" \' failed
# bullets of /tmp/claude-1000/bats-run-IGaouA/test/10/carrier.md
# --- want ---
# - [shared](shared.md) — fresh hook
# --- got ---
# - [shared](shared.md) — stale hook

bats: 9 passed, 1 failed — full log: /tmp/claude-1000/gitlore-bats.gchybs
```

Failed assertion: the exact-block equality on the committed carrier. Actual
value: `- [shared](shared.md) — stale hook`, i.e. the carrier as seeded, with no
composition on the commit path. Not a missing symbol, not a fixture error — the
run reached `assert_bullets`, which means `bash scripts/commit-memory.sh -m …`
exited 0 and `git -C memory/ddaanet show HEAD:MEMORY.md` produced a committed
carrier to compare.

## Test 2 — `the parent pre-commit hook composes the carrier before committing`

`tests/git_hook_pre_commit.bats`. Run:
`scripts/run-bats.sh tests/git_hook_pre_commit.bats`.

```
not ok 14 the parent pre-commit hook composes the carrier before committing
# (from function `assert_bullets' in file tests/helpers/tier-fixtures.bash, line 173,
#  in test file tests/git_hook_pre_commit.bats, line 244)
#   `assert_bullets "$BATS_TEST_TMPDIR/carrier.md" \' failed
# bullets of /tmp/claude-1000/bats-run-jdOspK/test/14/carrier.md
# --- want ---
# - [shared](shared.md) — fresh hook
# --- got ---
# - [shared](shared.md) — stale hook

bats: 13 passed, 1 failed — full log: /tmp/claude-1000/gitlore-bats.4lDDP9
```

Same failed assertion, same actual value, reached through the other entry point.
`bash "$HOOK"` ran unguarded (no `run`), so a non-zero hook exit would have
aborted the test before `assert_bullets`; it did not.

No pre-existing case in either suite regressed: 9/10 and 13/14 pass, the one
failure being the new case.

## The gitlink assertion, verified separately

Each test's second assertion — `git -C memory rev-parse HEAD:ddaanet` equals
`git -C memory/ddaanet rev-parse HEAD` — is unreachable in the red run, because
`assert_bullets` fails first and a bats test body runs under errexit. It is
asserted to be already true today, so it would be invisible either way; left
unverified it could equally be a latent second failure that only surfaces at
green.

Verified with a throwaway `tests/zz_probe_gitlink.bats` holding the same two
fixtures and only the gitlink assertion, run from the suite's own directory so
`PLUGIN_ROOT` resolves identically, then deleted: `2 passed, 0 failed`. Both
gitlink equalities hold against unchanged code, as the dispatch predicted. It
pins nothing on its own and is there to lock the tier-first ordering.

## Deviation from the dispatch — the `index-compose.sh` source line

The dispatch specified adding
`source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"` to `setup()` in both files,
on the ground that "neither suite sources any lib today" and `assert_bullets`
needs `gitlore_index_part`.

That premise is false. `tests/helpers/setup.bash:30-35` sources **every**
`scripts/lib/*.sh` at load time, for every suite that does `load helpers/setup`,
which both of these do. `gitlore_index_part` is therefore already in scope, and
the evidence is the red run itself: `assert_bullets` executed and produced its
want/got diff without the extra source line.

The line was omitted rather than added — it is dead weight that misstates how
the suites get their libraries. `index_compose.bats:8-12` carries a comment
explaining that same global sourcing, which is where the correct account lives.

Green does not depend on this either way; if the reviewer wants the line for
explicitness it costs nothing to add, but it should not carry the "neither suite
sources any lib" justification.

## Housekeeping

- Nothing committed. `git status --porcelain` shows exactly the two modified
  test files.
- `just precommit` deliberately not run: the suite is red by design.
- `shellcheck -s bash` clean on both files.
