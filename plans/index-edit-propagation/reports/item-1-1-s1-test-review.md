# Item 1.1 slice 1 — test review

Verdict: the slice is sound. Both tests are red on their assertion against
unchanged `scripts/`, for the cause the slice is about, and the green they
demand is reachable. One comment inaccuracy fixed. Nothing else changed, nothing
committed.

## Mechanical check

Re-run with `scripts/run-bats.sh`, from `/Users/david/code/gitlore`.

| suite | result |
|---|---|
| `tests/commit_memory.bats` | 9 passed, 1 failed |
| `tests/git_hook_pre_commit.bats` | 13 passed, 1 failed |

The one failure in each is the new case, and each fails inside `assert_bullets`
with the same want/got pair:

```
# --- want ---
# - [shared](shared.md) — fresh hook
# --- got ---
# - [shared](shared.md) — stale hook
```

No PASS, no ERROR. Both reach the assertion, which is only possible if the entry
point ran to completion. The reproduction matches the RED report exactly,
including the pass counts.

`shellcheck -s bash` clean on both files. `git diff --check` clean. Both files
are UTF-8 with no CR; the dash in the new assertion is U+2014 (`e2 80 94`), the
same byte sequence `seed_tier_bullet` and `seed_root_bullet` emit.

## Wrong-reason hunting

**The red comes from the cause under test, and the green is reachable.** This
was the one claim worth spending a probe on, because a fixture that
`gitlore_compose` refuses would be red forever and no implementation could fix
it. A throwaway `tests/zz_probe_compose_reachable.bats` ran the slice fixture
verbatim and then called `gitlore_compose memory` directly. It returned 0,
printed `composed memory/ddaanet/MEMORY.md`, and left the carrier reading
exactly `- [shared](shared.md) — fresh hook` with the root index untouched.
Neither `gitlore_compose_check` nor `gitlore_compose_check_pins` refuses this
store: the tier is mounted, listed in the manifest, sitting at the gitlink the
memory index records, and the root bullet's `ddaanet/` prefix names a mounted
tier. The probe was deleted.

**The fixture leaves the store dirty and the summary satisfies freshness.** The
red output proves both without a separate probe. The committed carrier reads
`stale hook`, which means `gitlore_sync_tiers_to_live` ran and committed it.
That call sits inside the `dirty = 1` branch and after the
`gitlore_commit_msg_freshness` gate returns `yes`. A store read as clean, or a
summary read as stale, would have left the tier uncommitted and
`git show HEAD:MEMORY.md` would have produced the seeded tier index with no
bullets at all.

**The exact-block equality is genuinely exact.** `assert_bullets` compares
`gitlore_index_part "$f" bullets` against the joined arguments with a single
string comparison. A dropped line, an extra line, a reorder and a wording drift
each fail it. On a bulletless index it compares empty against non-empty, so it
cannot go vacuous. The unprefixed carrier form asserted here is the form
`tests/index_compose.bats:373` already pins for the down projection.

**Whitespace safety.** Nothing new splits on whitespace. Both new cases quote
every expansion, including the two `$(git … rev-parse …)` substitutions inside
`[ … = … ]`. `assert_bullets` quotes internally. The fixture helpers used are
pre-existing and unchanged.

**bash 3.2 and BSD.** The new lines use `git -C`, redirection, `printf` and `[`.
`BATS_TEST_TMPDIR` needs bats 1.4 and both files declare
`bats_require_minimum_version 1.5.0`; `tests/index_compose.bats` and
`tests/cc_hook_index_compose.bats` already use it. No GNU-only tool or flag, no
bash 4 construct.

**Helper collisions.** The added `load helpers/tier-fixtures` introduces no name
clash. Across `setup.bash`, `fixtures.bash`, `divergence-fixtures.bash`,
`tier-fixtures.bash` and `triggers.bash` every function name is defined exactly
once.

## The deviation — the `index-compose.sh` source line

Ruling: **the omission stands.** No fix.

The RED report's premise checks out. `tests/helpers/setup.bash` sources every
`scripts/lib/*.sh` at load time, inside a `nullglob` loop at lines 30 to 35, and
both suites do `load helpers/setup`. `gitlore_index_part` is therefore already
in scope, which the red run itself demonstrates: `assert_bullets` executed and
produced its diff without the extra line. The dispatch's stated justification,
that neither suite sources any lib today, is false.

`tests/index_compose.bats` does carry its own `source` of `index-compose.sh`,
with a comment at lines 8 to 12 explaining that `load helpers/setup` already
handles the rest and that re-sourcing `util.sh` would die on its readonly
constants. That is a suite whose subject *is* `index-compose.sh`, so naming the
file under test there is meaningful. In `commit_memory.bats` and
`git_hook_pre_commit.bats` the subject is the commit path, and a source line
naming the compose library would assert a dependency the suite does not have.

## The gitlink assertion

Present and correctly written in both cases, comparing
`git -C memory rev-parse HEAD:ddaanet` against
`git -C memory/ddaanet rev-parse HEAD`.

Re-verified rather than taken on report. A throwaway
`tests/zz_probe_gitlink.bats` held the same fixture and only the gitlink
equality, for both entry points: `2 passed, 0 failed`. Both equalities hold
against unchanged code, so the assertion is not a latent second failure waiting
at green. It pins nothing on its own and is there to lock the tier-first
ordering at `scripts/lib/resolve.sh:900-905`. The probe was deleted.

Worth noting for the green phase: the block equality also catches a compose
placed *after* `gitlore_sync_tiers_to_live`, since the tier commit would then
record the pre-compose carrier. The two assertions overlap on that fault rather
than the gitlink one carrying it alone.

## Fix applied

One, in `tests/git_hook_pre_commit.bats`. The new case's opening comment read
"both call gitlore_sync_memory_to_live and nothing else". That is false of the
hook, which also stages the parent's gitlink after the sync returns
(`scripts/git-hooks/pre-commit:73-92`). The intended claim is that neither entry
point carries commit logic of its own. Rewritten to say that, and to name the
hook's remaining work.

Both suites re-run after the edit: still 9/1 and 13/1, still failing inside
`assert_bullets` on the same want/got pair. `shellcheck -s bash` still clean.

## Not flagged

Out of scope per the dispatch and left alone: `scripts/lib/resolve.sh` and
everything under `scripts/`, slice 2's dirty guard, slice 3's return-code
handling, all Phase 2, 3 and 4 files, and every pre-existing case in the two
suites.

One in-scope divergence from the dispatch that is not a defect: the
`commit_memory.bats` case does not write an approved summary to
`gitlore_commit_msg_file memory`. The dispatch called that write redundant for
this entry point, and it is — `scripts/commit-memory.sh:61-63` writes the file
itself from `-m` immediately before calling the sync, which satisfies the
freshness gate by construction. Omitting it removes a line that would have
implied the test needed it.

## Housekeeping

- Nothing committed. `git status --porcelain` shows the two modified test files
  plus this untracked `reports/` directory.
- `just precommit` deliberately not run: the suite is red by design.
- Both throwaway probes deleted; `tests/` holds no `zz_probe_*` file.
