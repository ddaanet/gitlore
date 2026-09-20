#!/usr/bin/env bats
# The pre-commit hook's carrier-composition path: staleness detection against
# a landed tier commit, retry after a half-landed compose, and the abort arms
# for a duplicate pointer or a welded index line.
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/tier-fixtures
load helpers/git-hook-pre-commit

# The shared base for both dirty-scope cases below: the slice-1 divergence —
# a stale tier carrier under a root index that already says otherwise — fully
# committed on BOTH sides (the tier's own history, then memory's), with HEAD
# one commit past `live`.
#
# The tier-side commit is not optional: `seed_tier_bullet` only writes the
# tier's working tree, and `git -C memory add -A` records a submodule's moved
# HEAD without ever committing inside it — so without it the submodule stays
# `m ddaanet` and `commit_memory_state` alone cannot make the store clean.
#
# HEAD past `live` is what lets a CLEAN store reach the guard at all:
# gitlore_sync_memory_to_live returns early when the store is clean AND HEAD
# equals `live`, so a clean fixture sitting at `live` never enters the function
# body, and its case would pass with the dirty=1 guard widened, with the
# compose call absent, and with the whole feature reverted. `commit_memory_state`
# already leaves HEAD one ahead, so the `branch -f` restates that shape rather
# than creating it — it is what keeps the fixture right if either helper stops
# producing it. The two checks at the end are what make the precondition
# non-negotiable: drifted back to HEAD == live, the negative below passes even
# against a SUT that composes a clean store, and nothing in it fails.
committed_stale_carrier_store() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  git -C memory/ddaanet add -A || return 1
  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q -m "carrier: stale hook" || return 1
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  commit_memory_state || return 1
  git -C memory branch -f live HEAD~1 || return 1
  [ "$(gitlore_memory_dirty memory)" = "0" ] || {
    echo "committed_stale_carrier_store: store is dirty; the clean case would not reach the guard" >&2
    return 1
  }
  [ "$(git -C memory rev-parse HEAD)" != "$(git -C memory rev-parse live)" ] || {
    echo "committed_stale_carrier_store: HEAD is at live; a clean store returns before the guard" >&2
    return 1
  }
}

@test "a clean store is not composed by the commit path" {
  committed_stale_carrier_store
  head_before=$(git -C memory rev-parse HEAD)

  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(gitlore_memory_dirty memory)" = "0" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  # Exact block, not a present/absent pair: "stale hook" is a variant of
  # "fresh hook", so no single fault could fail a negative on its own. The
  # discriminating assertion: composing here rewrites the carrier and the
  # store goes dirty.
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — stale hook'
}

@test "the same store, made dirty, IS composed" {
  # The positive that keeps the negative honest, over the same fixture
  # differing only in the guard's trigger input (dirty=0 vs dirty=1). Its own
  # test body, never appended to the negative: a bats body runs under
  # errexit, so a negative sitting behind a positive runs only in the case
  # where the positive already held.
  committed_stale_carrier_store

  # One uncommitted local fact makes the store dirty without touching the
  # tier side at all.
  printf -- '---\nname: local\ndescription: ""\n---\n\na local fact\n' > memory/local.md
  seed_root_bullet "local.md" "a local fact"
  # Written last: gitlore_commit_msg_freshness compares this file's mtime
  # against the newest file under memory/, and a summary older than the seeds
  # is stale.
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record a local fact\n' > "$msgfile"

  bash "$HOOK"

  git -C memory/ddaanet show HEAD:MEMORY.md > "$BATS_TEST_TMPDIR/carrier.md"
  assert_bullets "$BATS_TEST_TMPDIR/carrier.md" \
    '- [shared](shared.md) — fresh hook'
}

# The retry the landing record exists for, through the entry point whose
# retry runs on the summary file as it stands: the pre-commit hook. The first
# run composes and commits inside the tier, then loses memory's index.lock;
# the second must adopt its own landed tier commit and finish, which needs
# both the restamp on that failure and the landed-tier staging.
@test "a commit half-landed in a tier retries to completion from the hook" {
  half_landed_tier_fixture
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"
  # Whole-second mtimes compared with `>=`: a carrier written in the summary's
  # second would read fresh with no restamp at all.
  sleep 1
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr bash "$HOOK"
  [ "$status" -ne 0 ]
  [ -f "$lock" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]

  rm -f "$lock"
  run --separate-stderr bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record the shared fact" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a dirty carrier with a duplicate pointer aborts the commit and restamps the approval" {
  # The hook's own path through the abort commit-memory.sh already takes:
  # gitlore_sync_memory_to_live is the shared body, and here the retry runs on
  # the summary as it stands, so only the abort's restamp keeps it approved.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  # A fresh mount has no local `live`; one is created so a commit that lands
  # the tier would advance it, giving the "unmoved" assertion something to catch.
  git -C memory/ddaanet branch -f live
  seed_tier_bullet ddaanet shared.md "hook"
  seed_tier_bullet ddaanet shared.md "hook"
  seed_root_bullet "ddaanet/shared.md" "hook"
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"

  # Backdate the summary and every tracked memory file to one stamp, so
  # gitlore_commit_msg_freshness reads "yes" and the run reaches compose, and
  # a restamp reads newer even within the second the seeds were written.
  touch -t 200001010000 "$msgfile"
  while IFS= read -r -d '' f; do
    touch -t 200001010000 "$f"
  done < <(find memory -type f -not -path '*/.git/*' -print0)
  stamp_epoch=$(_gitlore_mtime "$msgfile")
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]

  head_before=$(git -C memory rev-parse HEAD)
  tier_head_before=$(git -C memory/ddaanet rev-parse HEAD)
  tier_live_before=$(git -C memory/ddaanet rev-parse live)
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: duplicate pointer path shared.md"* ]]
  # The duplicate line prints on the advisory arm too; these two name the arm.
  [[ "${output}${stderr}" == *"aborted"* ]]
  [[ "${output}${stderr}" != *"the commit went ahead"* ]]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$tier_live_before" ]
  [ -n "$(git -C memory/ddaanet status --porcelain -- MEMORY.md)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head_before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(_gitlore_mtime "$msgfile")" -gt "$stamp_epoch" ]
}

@test "a dirty root index with a welded line aborts the commit and restamps the approval" {
  # No tier: root's own index is the one carrying the change, so the abort has
  # to come from the root branch of the rc-1 arm rather than a tier's.
  make_parent_with_memory
  printf -- '- [A](a.md) — a- [B](b.md) — b\n' >> memory/MEMORY.md
  n=$(wc -l < memory/MEMORY.md | tr -d ' ')
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record a and b\n' > "$msgfile"

  # Backdate the summary and every tracked memory file to one stamp, so
  # gitlore_commit_msg_freshness reads "yes" and the run reaches compose, and
  # a restamp reads newer even within the second the seeds were written.
  touch -t 200001010000 "$msgfile"
  while IFS= read -r -d '' f; do
    touch -t 200001010000 "$f"
  done < <(find memory -type f -not -path '*/.git/*' -print0)
  stamp_epoch=$(_gitlore_mtime "$msgfile")
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]

  head_before=$(git -C memory rev-parse HEAD)
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory/MEMORY.md: line $n welds two pointer bullets"* ]]
  # The weld line prints on the advisory arm too; these two name the arm.
  [[ "${output}${stderr}" == *"aborted"* ]]
  [[ "${output}${stderr}" != *"the commit went ahead"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(_gitlore_mtime "$msgfile")" -gt "$stamp_epoch" ]
}

@test "an aborted compose keeps the approved summary usable" {
  # The case that would have caught slice 3 code review's Major 1: a partial
  # compose (rc 2) restamps whatever it DID write, so the approved summary
  # reads stale on the very next run and the retry is refused for a change the
  # summary already covers.
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  make_parent_with_memory
  make_tier_in_memory alpha
  make_tier_in_memory beta
  set_tier_manifest alpha beta
  seed_tier_bullet alpha shared.md "stale alpha"
  seed_root_bullet "alpha/shared.md" "fresh alpha"
  seed_tier_bullet beta shared.md "stale beta"
  seed_root_bullet "beta/shared.md" "fresh beta"
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record both facts\n' > "$msgfile"
  # gitlore_commit_msg_freshness compares whole-second mtimes with `>=`, so a
  # carrier written in the same second as the summary would still read fresh
  # and the defect this test exists to catch would not appear.
  sleep 1

  # gitlore_active_tiers walks the manifest in order (alpha, beta), and
  # gitlore_compose composes in that same order — so beta is the tier that
  # composes second. Blocking its write lets alpha's write land first (making
  # the tree newer than the summary) and then fail on beta, which is what
  # gitlore_compose's rc 2 requires. Blocking alpha instead would fail before
  # anything was written, and the msgfile would never go stale.
  head_before=$(git -C memory rev-parse HEAD)
  chmod a-w memory/beta

  run bash "$HOOK"
  chmod u+w memory/beta
  [ "$status" -ne 0 ]
  [ -f "$msgfile" ]
  # The comment above states the composition order; these assert it. Left to a
  # comment, a reordering inside gitlore_compose would void the case silently:
  # beta failing FIRST writes nothing, the summary never goes stale, and the
  # second run below passes whether or not the restamp is there.
  [[ "$output" == *"composed memory/alpha/MEMORY.md"* ]]
  [[ "$output" == *"could not write memory/beta/MEMORY.md"* ]]

  # No new summary written: this run relies entirely on the restamp restoring
  # the approval's freshness, which is the fix under test.
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head_before" ]
}
