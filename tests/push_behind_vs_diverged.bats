#!/usr/bin/env bats
# Behind is not diverged.
#
# git refuses a push of a merely-BEHIND ref with the same "(non-fast-forward)"
# it gives a genuinely diverged one, so a site that classifies on that text
# alone sends a store with nothing to publish into the merge flow. The
# preparation finds nothing to merge and reports a merge it could not prepare —
# naming a worktree that is clean, which is why this went unread in the field.
#
# Ancestry is the discriminator these tests pin, plus the invariant the push
# path reasons from: a store is detached AT `live` (D17), so the push publishes
# `live` while the merge preparation reasons from HEAD. When those two name
# different commits, neither diagnosis describes what is wrong, and the failed
# preparation used to leave HEAD moved onto the authority — a diagnosis with a
# side effect, which is what left a store silently un-adopted.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

CMD="$PLUGIN_ROOT/scripts/push-memory.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
}
teardown() { teardown_tmp_repo; }

# A memory store wired to a bare remote and already published. Mirrors
# push_memory.bats's setup; the tier cases mount before publishing, so the
# remote wiring is separated from the fixture build.
wire_memory_remote() {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  publish_memory
}

publish_memory() {
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

# Advance the memory remote's `live` from a throwaway clone, behind our back:
# the local store is then strictly BEHIND, with nothing of its own to publish.
advance_memory_remote() {
  local other
  other="$(mktemp -d "$TMP_REPO/other.XXXXXX")"
  git clone -q "$MEMORY_REMOTE" "$other"
  (
    cd "$other" || exit 1
    git checkout -q live
    printf 'remote-only\n' > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "remote-only"
    git push -q origin live
  )
  rm -rf "$other"
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

# A tier in the state SessionStart leaves it in: local `live` created from the
# remote, worktree detached at `live`.
mount_tier_at_live() {
  local tier="${1:-ddaanet}"
  make_tier_in_memory "$tier"
  git -C "memory/$tier" fetch -q origin "live:live"
  git -C "memory/$tier" checkout -q --detach live
}

# --- the preparation must not move a ref when it prepares nothing ---

@test "a preparation with nothing to merge leaves the store's HEAD where it was" {
  wire_memory_remote
  advance_memory_remote
  git -C memory fetch -q origin live
  # HEAD is contained in origin/live, so there is no merge to make. The old
  # implementation detached onto the authority first and discovered that after.
  before=$(git -C memory rev-parse HEAD)
  run --separate-stderr gitlore_prepare_merge memory origin/live live
  [ "$status" -eq 1 ]
  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
}

@test "a preparation resolves pending from the given ref, not a HEAD an earlier interrupted run displaced" {
  # The edify incident: a prior gitlore_prepare_merge staged a real merge
  # (checkout --detach onto the authority, MERGE_HEAD set) and the caller died
  # before gitlore_write_merge_state ran. HEAD is now sitting ON the authority;
  # local `live` is untouched and still names the real divergent commit. A
  # retry that reads pending from HEAD would misdiagnose genuine divergence as
  # "authority already contains HEAD" and silently drop it.
  wire_memory_remote
  advance_memory_remote
  add_memory_commit LOCAL.md "local-only"
  git -C memory fetch -q origin live
  live_before=$(git -C memory rev-parse live)

  git -C memory update-ref refs/gitlore/pending "$(git -C memory rev-parse HEAD)"
  git -C memory checkout -q --detach origin/live

  run --separate-stderr gitlore_prepare_merge memory origin/live live
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse -q --verify MERGE_HEAD)" = "$live_before" ]
}

# --- remote flavor: behind, diverged, drift ---

@test "memory behind its remote is taken by fast-forward, not routed into a merge" {
  # A push is attempt → take → attempt again (D49), so being behind is resolved
  # here rather than handed back as an errand. What must not happen either way
  # is a merge preparation against a store with nothing to merge.
  wire_memory_remote
  advance_memory_remote
  remote_sha=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" != *"memory merge prepared"* ]]
  [[ "$msg" != *"could not prepare"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse live)" = "$remote_sha" ]
  run ! git -C memory rev-parse -q --verify refs/gitlore/pending
}

@test "a remote that moved on its own is not reported as commits this run published" {
  # origin/live advances during the push's own fetch, so the before/after
  # comparison the report is built on moves even though this run sent nothing.
  wire_memory_remote
  advance_memory_remote

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" != *"published 1 commit(s)"* ]]
}

@test "memory genuinely diverged from its remote still prepares a merge" {
  wire_memory_remote
  advance_memory_remote
  add_memory_commit LOCAL.md "local-only"

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  msg="$output$stderr"
  [[ "$msg" == *"memory merge prepared"* ]]
}

@test "a store whose HEAD is behind its own live is reported as drift, and no ref moves" {
  wire_memory_remote
  add_memory_commit LOCAL.md "local-only"
  # `live` ahead, HEAD pinned behind it: the field shape, where `push origin
  # live` is refused on a ref the merge preparation never looks at.
  git -C memory checkout -q --detach HEAD~
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  msg="$output$stderr"
  [[ "$msg" == *"is not at its local 'live'"* ]]
  [[ "$msg" == *"checkout --detach live"* ]]
  [[ "$msg" != *"memory merge prepared"* ]]
  [[ "$msg" != *"could not prepare"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
}

@test "a store whose HEAD is ahead of its own live has 'live' advanced, then publishes" {
  # The direction that would publish LESS than the store holds: `push origin
  # live` succeeds while the gitlink the parent records — HEAD — never reaches
  # the remote, which is the lockstep guarantee failing silently. It is also the
  # one direction that cannot mean anything else, so the preflight advances
  # `live` rather than sending the user off to run the one git command it would
  # have named.
  wire_memory_remote
  add_memory_commit LOCAL.md "local-only"
  git -C memory checkout -q --detach HEAD
  git -C memory branch -f live HEAD~
  head_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"stranded behind HEAD"* ]]
  [[ "$msg" != *"is not at its local 'live'"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$head_before" ]
  # The lockstep guarantee, met rather than reported: what the parent's gitlink
  # records is what the remote now holds.
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$head_before" ]
}

@test "a store stranded at its remote's commit publishes instead of failing again" {
  # The 0.5.0 field shape: a merge preparation that could not continue had
  # checked HEAD out at `origin/live` and left `live` where it was, so every
  # later push was refused on a ref no diagnosis looked at. Nothing here is this
  # repo's to publish — the run has to end clean anyway.
  wire_memory_remote
  advance_memory_remote
  git -C memory fetch -q origin live
  remote_sha=$(git -C memory rev-parse origin/live)
  git -C memory checkout -q --detach origin/live
  [ "$(git -C memory rev-parse live)" != "$remote_sha" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"stranded behind HEAD"* ]]
  [[ "$msg" != *"could not prepare"* ]]
  [[ "$msg" != *"is not at its local 'live'"* ]]
  [ "$(git -C memory rev-parse live)" = "$remote_sha" ]
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$remote_sha" ]
}

# --- tier loop: one behind tier is not a failed push ---

@test "a tier behind its remote is taken by the push, not left as an errand" {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  mount_tier_at_live ddaanet
  publish_memory
  remote_sha=$(push_tier_fact ddaanet "- [upstream](u.md) — hook")

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"ddaanet"* ]]
  [[ "$msg" != *"memory merge prepared"* ]]
  [[ "$msg" != *"could not prepare"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
}

# --- local flavor: the same misread against a store's own `live` ---

@test "memory HEAD behind its own live is reported as drift rather than an unpreparable merge" {
  make_parent_with_memory
  add_memory_commit LOCAL.md "local-only"
  git -C memory checkout -q --detach HEAD~
  head_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr gitlore_sync_memory_to_live memory
  [ "$status" -eq 1 ]
  msg="$output$stderr"
  [[ "$msg" == *"is not at its local 'live'"* ]]
  [[ "$msg" != *"could not prepare"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}
