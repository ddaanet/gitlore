#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/merge-memory

# Store-level takes: fast-forward, no-op, stranded/diverged refs, the
# merge-prepared continuation, and a store or a tier with no remote to take
# from.

# Leave a store in the state a failed merge preparation produces: HEAD checked
# out at the commit `origin/live` names, and the local `live` — the ref a push
# sends and the only one a fast-forward advances — left where it was. From that
# moment the remote is contained in HEAD, so an ancestry test that reads HEAD
# alone calls the store finished while `live` stays behind.
strand_live_behind_head() {
  local store="$1"
  git -C "$store" fetch -q origin +refs/heads/live:refs/remotes/origin/live
  git -C "$store" checkout -q --detach origin/live
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

@test "advances a root store's local 'live' left stranded behind HEAD" {
  # The remote is contained in HEAD, so there is nothing to take — but `live`,
  # the ref the next push sends, is behind, and that push is refused again for
  # a reason neither ref explains. /gitlore:merge is the documented remedy, so
  # it is the thing that has to move `live`.
  wire_memory_remote
  behind=$(git -C memory rev-parse live)
  push_memory_fact
  remote_sha=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  strand_live_behind_head memory
  [ "$(git -C memory rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse live)" = "$behind" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse live)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse HEAD)" = "$remote_sha" ]
  [[ "$output$stderr" == *"stranded behind HEAD"* ]]
  # The repair is local: taking still publishes nothing.
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$remote_sha" ]
}

@test "advances a TIER's local 'live' left stranded behind HEAD" {
  # The shape the field incident had: the store the failed preparation moved was
  # a tier, and a tier is the store /gitlore:merge exists to advance.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  # The mount leaves the tier on `main` with no local `live`; the ref has to
  # exist, and be behind, for it to be strandable.
  git -C memory/ddaanet branch -f live origin/live
  behind=$(git -C memory/ddaanet rev-parse live)
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')
  strand_live_behind_head memory/ddaanet
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$behind" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [[ "$output$stderr" == *"tier 'ddaanet'"* ]]
  [[ "$output$stderr" == *"stranded behind HEAD"* ]]
}

@test "reports a store whose HEAD and 'live' have diverged instead of moving either" {
  # Only a `live` the current HEAD contains is unambiguously stranded. When each
  # ref holds a commit the other lacks, which one was intended is not
  # recoverable from the refs, so the repair declines and says so.
  wire_memory_remote
  base=$(git -C memory rev-parse HEAD)
  (
    cd memory || exit 1
    git checkout -q live
    printf 'on-live\n' > ON-LIVE.md
    git add -A
    GITLORE_MEMORY_COMMIT=1 git commit -q -m "on live only"
    git checkout -q --detach "$base"
    printf 'on-head\n' > ON-HEAD.md
    git add -A
    GITLORE_MEMORY_COMMIT=1 git commit -q -m "on HEAD only"
  )
  head=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
  [ "$(git -C memory rev-parse live)" = "$live" ]
  [[ "$output$stderr" == *"have each moved since they last agreed"* ]]
  # The repair runs before the no-op report, so a store that is about to fail is
  # never first told it holds everything it needs.
  [[ "$output$stderr" != *"already holds everything"* ]]
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

@test "a merge aborted by hand is disposed of and re-prepared, not refused over" {
  # The observed producer of a state file without MERGE_HEAD: an agent asked to
  # revert to the pre-merge state runs a plain `git merge --abort` in the store,
  # which clears MERGE_HEAD and resets the index while gitlore's state file and
  # its three briefing artifacts stay put. Both this entry point and resolve.sh
  # used to refuse over what was left, with no path back.
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
  bash "$CMD" || true
  statefile=$(gitlore_merge_state_file memory)
  pending=$(jq -r .source_ref "$statefile")
  [ -n "$pending" ]

  git -C memory merge --abort
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD || true)" ]
  [ -f "$statefile" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [[ "$all" == *"nothing landed"* ]]
  [[ "$all" == *"leftover state is discarded"* ]]
  [[ "$all" == *"memory merge prepared"* ]]
  # The same merge, against the same divergent side, still marked reconcile-only.
  [ "$(jq -r .source_ref "$statefile")" = "$pending" ]
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

