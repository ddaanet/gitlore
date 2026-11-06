#!/usr/bin/env bats
# The continuation half of the tier-divergence suite: a landed merge must
# reach the tier's own store, survive the next pin, and /gitlore:resolve must
# find a tier divergence on its own even with nothing staged yet.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/tier-divergence

# --- the continuation follows the merge to its store ---

@test "continue-after-merge commits in the tier, not in memory" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet
  mem_before=$(git -C memory rev-parse HEAD)
  bash "$PRE_PUSH" || true
  # Stand in for the memory-merger sub-agent: accept the merged tree as-is.
  git -C memory/ddaanet add -A

  run bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]

  # The merge commit is the TIER's, and both its live refs now hold it.
  head=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-list --count --merges "$head" -1)" = "1" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$head" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$head" ]
  # Memory took no commit at all: the run that follows records the tier.
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
  [ ! -f "$(tier_state_file ddaanet)" ]
}

# The window between "merge landed" and "the next run records it". A landed
# merge has staged nothing, so the tier sits ahead of the gitlink in memory's
# INDEX. SessionStart moves no module: the tier stays on the merge, `live` keeps
# it, and the next take records it.
@test "a landed tier merge a SessionStart finds ahead of the pin stays on the merge and is recorded by the next take" {
  make_parent_with_memory
  git -C memory push -q origin live
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet
  pinned=$(git -C memory rev-parse HEAD:ddaanet)
  bash "$PRE_PUSH" || true
  git -C memory/ddaanet add -A
  bash "$RESOLVE" continue-after-merge
  merged=$(git -C memory/ddaanet rev-parse HEAD)
  # The fixture has to give the session something to move: the tier is off the
  # commit memory records, and memory has not committed the move.
  [ "$merged" != "$pinned" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pinned" ]

  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$merged" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$merged" ]

  run --separate-stderr bash "$PLUGIN_ROOT/scripts/merge-memory.sh"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$merged" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$merged" ]
  grep -qF -- '- [org fact](f.md) — ours' memory/ddaanet/MEMORY.md
  grep -qF -- '- [their fact](t.md) — theirs' memory/ddaanet/MEMORY.md
}

@test "a tier's prepared merge is continued in the tier, not memory" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet
  bash "$PRE_PUSH" || true
  [ -f "$(tier_state_file ddaanet)" ]
  pending=$(git -C memory/ddaanet rev-parse "$GITLORE_PENDING_REF")

  # A later gate meets the prepared merge: it is continued where it was
  # prepared, and memory has nothing prepared in it at all.
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  all="$output$stderr"
  [[ "$all" == *"continue-after-merge"* ]]
  [[ "$all" == *"ddaanet"* ]]
  [ "$(git -C memory/ddaanet rev-parse MERGE_HEAD)" = "$pending" ]
  [ ! -f "$(gitlore_merge_state_file memory)" ]
}

@test "a merge prepared in two stores is refused, not guessed at" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  printf '{"flavor":"head-vs-live","store":"%s"}\n' "$(cd memory && pwd)" \
    > "$(gitlore_merge_state_file memory)"
  printf '{"flavor":"head-vs-live","store":"%s"}\n' "$(cd memory/ddaanet && pwd)" \
    > "$(tier_state_file ddaanet)"

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  all="${output}${stderr}"
  [[ "$all" == *"more than one store"* ]]
  [[ "$all" == *"ddaanet"* ]]
}

@test "no merge state anywhere is reported as such" {
  make_parent_with_memory
  mount_tier_at_live ddaanet

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"no merge state file"* ]]
}

# --- /gitlore:resolve finds a tier divergence on its own ---

@test "the standalone resolver detects a tier divergence" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  all="${output}${stderr}"
  [[ "$all" == *"gitlore: memory merge prepared"* ]]
  [[ "$all" == *"memory/ddaanet"* ]]
}

@test "the standalone resolver is healthy when every store is in sync" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  commit_sections "memory: record the org fact"
  bash "$PRE_PUSH"

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 0 ]
  [[ "${output}${stderr}" == *"healthy"* ]]
}

@test "a stale tier merge state blocks the push instead of pushing over it" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  printf '{"flavor":"head-vs-remote","store":"%s"}\n' "$(cd memory/ddaanet && pwd)" \
    > "$(tier_state_file ddaanet)"

  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"manual intervention required"* ]]
}
