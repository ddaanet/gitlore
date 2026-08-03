#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth

CMD="$PLUGIN_ROOT/scripts/merge-memory.sh"

# /gitlore:merge is the half of /gitlore:push that takes without publishing, and
# under pinned tiers it is the only path by which a tier advances at all. What is
# pinned here is that direction: what each store ends up holding, what reaches
# the root index, and that nothing of this repo's leaves it.
setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
}
teardown() { teardown_tmp_repo; }

wire_memory_remote() {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

# Publish a commit to the memory remote that this clone does not have.
push_memory_fact() {
  local work
  work="$(mktemp -d "$TMP_REPO/clone.XXXXXX")"
  (
    cd "$work" || exit 1
    git clone -q "$MEMORY_REMOTE" .
    git checkout -q live
    printf 'remote-only\n' > REMOTE.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -q -m "remote fact"
    git push -q origin live
  )
  rm -rf "$work"
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

@test "rejects arguments" {
  run bash "$CMD" origin
  [ "$status" -eq 2 ]
}

@test "fast-forwards memory onto its remote and publishes nothing" {
  wire_memory_remote
  before=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  push_memory_fact
  remote_sha=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  run bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse live)" = "$remote_sha" ]
  [ -f memory/REMOTE.md ]
  # Detached, per the branch model.
  run git -C memory symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  # And the remote did not move: taking is not publishing.
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$remote_sha" ]
  [ "$before" != "$remote_sha" ]
}

@test "says so when a store already holds everything its remote does" {
  wire_memory_remote
  run bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already holds everything"* ]]
}

@test "leaves a store whose remote it is ahead of alone" {
  # Local commits awaiting publication are /gitlore:push's business. Taking
  # nothing is the right answer, and it must not read as a divergence.
  wire_memory_remote
  (
    cd memory || exit 1
    git checkout -q live
    printf 'local\n' > LOCAL.md
    git add -A
    git commit -q -m "local, unpublished"
    git checkout -q --detach live
  )
  head=$(git -C memory rev-parse HEAD)
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
  [[ "$output$stderr" != *"merge prepared"* ]]
}

@test "refuses a store with uncommitted changes instead of checking out over them" {
  wire_memory_remote
  push_memory_fact
  printf -- '- [dirty](dirty.md) — not committed yet\n' >> memory/MEMORY.md
  head=$(git -C memory rev-parse HEAD)
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"uncommitted changes"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
  grep -qF 'dirty.md' memory/MEMORY.md
}

@test "prepares a merge that will NOT publish when a store has diverged" {
  wire_memory_remote
  (
    cd memory || exit 1
    git checkout -q live
    printf 'local\n' > LOCAL.md
    git add -A
    git commit -q -m "local, unpublished"
    git checkout -q --detach live
  )
  push_memory_fact
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  # The mark the continuation reads: this merge reconciles, it does not share.
  statefile=$(gitlore_merge_state_file memory)
  [ "$(jq -r .publish "$statefile")" = "no" ]
}

@test "a push-prepared merge is not marked no-publish" {
  # The flag must not leak into the gates: a merge a refused push prepared
  # exists precisely so that push can go through.
  wire_memory_remote
  (
    cd memory || exit 1
    git checkout -q live
    printf 'local\n' > LOCAL.md
    git add -A
    git commit -q -m "local, unpublished"
    git checkout -q --detach live
  )
  push_memory_fact
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/push-memory.sh"
  [ "$status" -eq 1 ]
  statefile=$(gitlore_merge_state_file memory)
  [ "$(jq -r '.publish // ""' "$statefile")" = "" ]
}

@test "fails when a TIER has no remote configured" {
  # A tier exists to be shared, so one with no remote is a misconfiguration and
  # the whole reconcile stops on it.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet remote remove origin
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"no remote configured"* ]]
}

@test "memory with no remote is nothing to take, and the tiers still reconcile" {
  # The counterpart of the push side: a local-only memory store is a supported
  # end state, and its remote-lessness must not withhold the shared half.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')
  git -C memory remote remove origin
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to take"* ]]
  # The tier took what its own remote held.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
}

@test "a synced placeholder origin is nothing to take, not an unreachable remote" {
  wire_memory_remote
  # What `git submodule sync` leaves on a local-only install.
  git -C memory remote set-url origin "$TMP_REPO/.git/gitlore-placeholder"
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to take"* ]]
  [[ "$output$stderr" != *"could not fetch"* ]]
}

@test "fast-forwards a pinned tier and adopts its lines into the root index" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')

  run bash "$CMD"
  [ "$status" -eq 0 ]
  # The tier moved off its gitlink — the one operation that is allowed to do it.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$gitlink" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]
  # Adopted: the arrived line is in the always-loaded root index, prefixed.
  grep -qF -- '- [upstream](ddaanet/upstream.md) — published by another repo' memory/MEMORY.md
  # The moved gitlink and the recomposed index are one memory change, left for
  # the FR11 commit — and the user is told rather than left to find it.
  [[ "$output" == *"uncommitted changes"* ]]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$gitlink" ]
}

@test "landing a merge-prepared merge advances local live but publishes nothing" {
  # The end of the no-publish path: the continuation reads the mark and stops
  # after the local fast-forward, which is the whole difference from a push.
  wire_memory_remote
  (
    cd memory || exit 1
    git checkout -q live
    printf 'local\n' > LOCAL.md
    git add -A
    git commit -q -m "local, unpublished"
    git checkout -q --detach live
  )
  push_memory_fact
  remote_before=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]

  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"merged without publishing"* ]]
  # The merge landed locally: HEAD is the merge commit and live followed it.
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
  [ -f memory/LOCAL.md ]
  [ -f memory/REMOTE.md ]
  # And the remote is exactly where it was.
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$remote_before" ]
}

@test "a tier fast-forward publishes nothing of this repo's" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  mem_remote_before=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo' >/dev/null
  tier_remote_before=$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)

  run bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$mem_remote_before" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$tier_remote_before" ]
}
