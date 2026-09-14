#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/tier-fixtures

HOOK="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

@test "exits 0 when gitlore is not configured" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "exits 0 when memory clean and at live" {
  make_parent_with_memory
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "exits 1 with hint when memory dirty and no approved summary" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"approved commit summary"* ]] || \
    [[ "${output}${stderr}" == *"Prepare a summary"* ]]
  [[ "${output}${stderr}" == *blockquote* ]]   # present as a draft (> ...), not a code fence
}

@test "dirty-no-summary hint interpolates the canonical memory-approval clause" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  clause=$(cat "$PLUGIN_ROOT/reference/memory-approval-clause.txt")
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"$clause"* ]]
}

@test "commits and ff-pushes to live when summary is fresh" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  bash "$HOOK"
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  [ ! -f "$msgfile" ]
}

@test "a failed memory commit is reported, not silently treated as success" {
  # set -e is transitively off inside gitlore_sync_memory_to_live when it is
  # called as `f || exit $?` (SC2310) — so an unchecked `add -A`/`commit`
  # failure used to fall through to `rm -f "$msgfile"` (deleting the approved
  # summary) and a no-op `push . HEAD:live` that reports success. Force the
  # `add -A` inside the memory store to fail for real via a stranded index.lock
  # in its actual gitdir (not the parent's).
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  mem_gitdir=$(git -C memory rev-parse --git-dir)
  : > "$mem_gitdir/index.lock"

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  rm -f "$mem_gitdir/index.lock"

  [ "$status" -ne 0 ]
  # The approved summary must survive a failed commit, not be deleted.
  [ -f "$msgfile" ]
  # Memory is still dirty and uncommitted — no phantom success.
  [ -n "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory log -1 --pretty=%s)" != "memory: add notes" ]
}

@test "exits 1 with memory-merger directive when branch diverged from live" {
  make_parent_with_memory
  # `live` advances behind the detached worktree's back (D17 branch model:
  # `live` is never checked out, so this is plumbing, not a checkout dance).
  advance_branch_with_file memory live LIVE.md live-only "Diverging commit on live"
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"flavor=head-vs-live"* ]]
  [[ "$output$stderr" == *"continue-after-merge"* ]]
}

@test "resolves PLUGIN_ROOT from gitlore.hooksDir when CLAUDE_PLUGIN_ROOT is unset" {
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  unset CLAUDE_PLUGIN_ROOT
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "commit path leaves HEAD detached at the advanced live" {
  # The D17 branch model's core invariant: the commit path must never attach
  # HEAD to a branch, and `live` must land on the new commit.
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  bash "$HOOK"
  run git -C memory symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  head=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$head" = "$live" ]
  # `live` is the only branch the commit path touches — no per-worktree branch
  # is created or advanced alongside it.
  run git -C memory for-each-ref --format='%(refname:short)' --points-at HEAD refs/heads
  [ "$output" = "live" ]
}

@test "a memory pointer that cannot be staged is reported, not a bare git error" {
  # Both staging branches end the same way — the commit records a stale memory
  # SHA — so both have to say so. Without a message `set -e` aborts the commit
  # on git's own "Unable to create index.lock" and nothing connects that to the
  # memory pointer. This is the branch git takes when the hook runs with no
  # GIT_INDEX_FILE (a direct invocation, or a hook manager that does not export
  # it).
  make_parent_with_memory
  # A stranded lock is the realistic cause, and it fails `git add` for real.
  : > .git/index.lock

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  rm -f .git/index.lock
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"pointer could not be staged"* ]]
  [[ "$output$stderr" == *"stale memory SHA"* ]]
}

@test "ignores parent GIT_DIR/GIT_INDEX_FILE leaked by 'git commit'" {
  # Regression: when git invokes the pre-commit hook, it sets GIT_DIR /
  # GIT_INDEX_FILE / GIT_WORK_TREE to relative paths under the parent repo.
  # `git -C memory <cmd>` inherits them and tries to resolve `.git/index` under
  # the submodule's gitfile, producing "fatal: .git/index: index file open
  # failed: Not a directory". The hook must unset these before touching the
  # submodule. Reproduced before fix; this test pins the fix.
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  # Simulate the leaked env. Relative paths matter — git uses them under
  # whatever CWD `git -C ...` switches to.
  export GIT_DIR=.git
  export GIT_INDEX_FILE=.git/index
  export GIT_WORK_TREE=.

  # Git's message, not gitlore's, so the pairing has to provoke it: the same
  # leaked environment, aimed at the submodule the hook works in. One assertion
  # shows the message is still what this git prints and that this fixture
  # reaches the producer; the other shows the hook clears the leak first.
  run --separate-stderr git -C memory status --porcelain
  [ "$status" -ne 0 ]
  [[ "${output}${stderr}" == *"$GITLORE_T_LEAKED_GITDIR"* ]]

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
  [ "$status" -eq 0 ]
  [[ "${output}${stderr}" != *"$GITLORE_T_LEAKED_GITDIR"* ]]
  # And the commit-and-push path actually fired:
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
}

@test "ignores parent GIT_COMMON_DIR/GIT_OBJECT_DIRECTORY leaked in a linked worktree" {
  # Regression: in a linked parent worktree git exports GIT_COMMON_DIR (and
  # GIT_OBJECT_DIRECTORY) alongside GIT_DIR. A hand-picked 4-var unset leaves
  # GIT_COMMON_DIR set, silently redirecting the submodule's refs/objects to the
  # parent's common dir. The hook must clear the full local-env-var set. This
  # points the parent's store at a bogus path: if the hook leaked it, the
  # submodule sync would touch that path and fail or write the wrong refs.
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  bogus="$TMP_REPO/.bogus-common-dir"
  mkdir -p "$bogus"
  export GIT_COMMON_DIR="$bogus"
  export GIT_OBJECT_DIRECTORY="$bogus/objects"

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  unset GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
  [ "$status" -eq 0 ]
  # The submodule's own live ref advanced — refs were written to the submodule
  # store, not the bogus parent common dir.
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  [ ! -e "$bogus/refs/heads/live" ]
}

@test "exits 0 in a session-less linked worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  [ ! -e "$WT/memory/.git" ]   # git created the gitlink dir but did not init the submodule
  cd "$WT"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  rm -rf "$WT"
}

@test "the parent pre-commit hook aborts on an off-pin tier" {
  # The second entry point for the reason Item 1.1 slice 1 gives: one shared
  # body (gitlore_sync_memory_to_live), two callers, and what is at stake is
  # what reaches the tier's remote. Same fixture as the commit-memory case.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"

  head_before=$(git -C memory rev-parse HEAD)
  pin_before=$(git -C memory rev-parse ":ddaanet")
  run bash "$HOOK"
  [ "$status" -ne 0 ]
  # Names WHY it aborted, so a different abort could not satisfy this case.
  [[ "$output" == *"moved off the commit the memory store records for it"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  # The carrier, in the worktree rather than at HEAD: the abort means nothing
  # was committed on either side, and seed_tier_bullet only ever wrote the
  # worktree, so the tier's HEAD:MEMORY.md would be the pre-seed file and pin
  # nothing about what composition was stopped from doing. Exact block, not a
  # grep: "stale hook" is a variant of the "fresh hook" a completed compose
  # would leave, so no single fault could fail a present/absent pair.
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — stale hook'
}

@test "the parent pre-commit hook composes the carrier before committing" {
  # Same store as the commit-memory case, driven through the other entry point.
  # Neither entry point carries commit logic of its own — gitlore_sync_memory_to_live
  # is the shared body, and the hook's remaining work is staging the parent
  # gitlink afterwards — so one compose there has to reach both.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  # Written last: gitlore_commit_msg_freshness compares this file's mtime against
  # the newest file under memory/, and a summary older than the seeds is stale.
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"

  bash "$HOOK"

  # Exact block, not a present/absent pair: "stale hook" is a variant of
  # "fresh hook", so no single fault could fail a negative on its own.
  git -C memory/ddaanet show HEAD:MEMORY.md > "$BATS_TEST_TMPDIR/carrier.md"
  assert_bullets "$BATS_TEST_TMPDIR/carrier.md" \
    '- [shared](shared.md) — fresh hook'

  # The memory commit records the tier commit that carries the composed carrier,
  # not the one before it — the tier-first ordering, locked against a reshuffle.
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
}

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
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -ne 0 ]
  [[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: duplicate pointer path shared.md"* ]]
  # The duplicate line prints on the advisory arm too; these two name the arm.
  [[ "${output}${stderr}" == *"aborted"* ]]
  [[ "${output}${stderr}" != *"the commit went ahead"* ]]
  [ -n "$(git -C memory/ddaanet status --porcelain -- MEMORY.md)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head_before" ]
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
