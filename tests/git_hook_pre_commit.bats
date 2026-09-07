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
# pushed one commit past live. `seed_tier_bullet` only writes the tier's
# working tree; without a commit inside memory/<tier> itself, that submodule
# stays "modified content" forever and `commit_memory_state` alone cannot make
# the store clean — `git -C memory add -A` records a submodule's moved HEAD,
# never commits inside it. And a clean store built the obvious way — HEAD left
# at whatever make_tier_in_memory last fast-forwarded `live` onto — never
# reaches the dirty=1 guard under test at all: gitlore_sync_memory_to_live
# returns early when the store is clean AND HEAD equals live. Forcing HEAD one
# commit ahead of `live` instead makes the function skip the dirty branch and
# go straight to the HEAD:live fast-forward — the guard under test.
committed_stale_carrier_store() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  git -C memory/ddaanet add -A || return 1
  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q -m "carrier: stale hook" || return 1
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  commit_memory_state
  git -C memory branch -f live HEAD~1
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
