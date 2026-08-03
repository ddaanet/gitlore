#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

CMD="$PLUGIN_ROOT/scripts/push-memory.sh"

# Shared with pre_push_hook.bats by construction: push-memory.sh and the pre-push
# hook both call gitlore_push_stores, so these cases pin the STANDALONE entry
# point's own contract — its guards, its argument handling, and the report it
# prints, none of which the hook has. The publish semantics themselves are the
# hook suite's, and a regression in them turns both suites red.
setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
}
teardown() { teardown_tmp_repo; }

# Give the repo a memory store wired to a bare remote, already published, then
# add one unpublished memory commit. Mirrors pre_push_hook.bats's setup.
wire_memory_remote() {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

add_memory_commit() {
  (
    cd memory || exit 1
    git checkout -q live
    printf 'new-fact\n' > "${1:-FACT.md}"
    git add -A
    git commit -q -m "${2:-Add fact}"
  )
}

@test "exits 0 with a note when the repo has no gitlore-memory submodule" {
  run bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no gitlore-memory submodule"* ]]
}

@test "exits 0 in a session-less worktree where the memory worktree is absent" {
  wire_memory_remote
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT"
  run bash -c "cd '$WT' && bash '$CMD'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not checked out in this worktree"* ]]
  git worktree remove --force "$WT"
}

@test "rejects arguments: approval belongs to the commit, not the push" {
  wire_memory_remote
  run --separate-stderr bash "$CMD" -m "a summary"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"usage:"* ]]
}

@test "publishes memory live to its origin" {
  wire_memory_remote
  add_memory_commit
  run bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse live)" = "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" ]
}

@test "reports how many commits each store published, and where its remote now sits" {
  wire_memory_remote
  add_memory_commit A.md "first"
  add_memory_commit B.md "second"
  run bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"published 2 commit(s)"* ]]
  [[ "$output" == *"$(git -C memory rev-parse --short live)"* ]]
}

@test "says nothing needed publishing when every store is already up to date" {
  wire_memory_remote
  run bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]]
  [[ "$output" != *"published"* ]]
}

@test "names uncommitted memory as NOT published rather than implying it landed" {
  wire_memory_remote
  add_memory_commit
  printf 'pending\n' > memory/UNCOMMITTED.md
  run bash "$CMD"
  [ "$status" -eq 0 ]
  # The committed work still goes out ...
  [ "$(git -C memory rev-parse live)" = "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" ]
  # ... and the residue is called out by name, not left to be assumed published.
  [[ "$output" == *"NOT published"* ]]
  [[ "$output" == *"memory"* ]]
}

@test "says memory stays local when it has no remote, and offers /gitlore:resolve" {
  wire_memory_remote
  add_memory_commit
  git -C memory remote remove origin
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"no remote of its own"* ]]
  [[ "$stderr" == *"/gitlore:resolve"* ]]
}

@test "reads a synced placeholder origin as no remote, not as an unreachable one" {
  wire_memory_remote
  add_memory_commit
  # What `git submodule sync` leaves on a local-only install: the .gitmodules
  # placeholder, absolutized against the superproject's location.
  git -C memory remote set-url origin "$TMP_REPO/.git/gitlore-placeholder"
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"no remote of its own"* ]]
  # Not a network diagnosis: there is no host here to be unreachable.
  [[ "$stderr" != *"unreachable"* ]]
}

@test "publishes a mounted tier when memory itself has no remote" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live
  tier_remote="$TMP_REPO/.bare-ddaanet.git"
  set_tier_manifest ddaanet
  (
    cd memory/ddaanet || exit 1
    printf 'tier-fact\n' > TIERFACT.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -q -m "tier fact"
    git push -q . HEAD:live
  )
  # The store that is shared is the tier; memory's own remote-lessness is a
  # deliberate configuration and must not withhold it.
  git -C memory remote remove origin
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$(git --git-dir="$tier_remote" rev-parse live)" ]
  [[ "$output" == *"ddaanet"* ]]
}

@test "prepares a merge and yields when the memory remote has diverged" {
  wire_memory_remote
  add_memory_commit
  (
    cd "$(mktemp -d "$TMP_REPO/clone.XXXXXX")" || exit 1
    git clone -q "$MEMORY_REMOTE" .
    git checkout -q live
    printf 'remote-only\n' > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "remote-only commit"
    git push -q origin live
  )
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  # The marker the push skill routes on -- same directive the pre-push hook emits.
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  # Nothing may be reported as published on the failing path.
  [[ "$output" != *"published"* ]]
}

@test "publishes a mounted tier to its own remote alongside memory" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  # A fresh mount checks out the remote's default branch; local `live` (the ref
  # the push loop publishes) does not exist until it is fetched.
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live
  tier_remote="$TMP_REPO/.bare-ddaanet.git"
  set_tier_manifest ddaanet
  (
    cd memory/ddaanet || exit 1
    printf 'tier-fact\n' > TIERFACT.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -q -m "tier fact"
    git push -q . HEAD:live
  )
  run bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$(git --git-dir="$tier_remote" rev-parse live)" ]
  [[ "$output" == *"ddaanet"* ]]
}
