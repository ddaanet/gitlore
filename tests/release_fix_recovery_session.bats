#!/usr/bin/env bats
# Release-review fixes over the merge continuation and SessionStart's reports.
#
# - `continue-after-merge` met by a store whose MERGE_HEAD a checkout cleared
#   (docs/references/merge-state-recovery.md: `git checkout`, including the
#   no-op re-checkout `submodule update` runs, unlinks MERGE_HEAD and leaves the
#   staged result) commits nothing: a commit there has one parent and drops the
#   pending side. It refuses and names /gitlore:resolve, whose guard repairs the
#   shape.
# - SessionStart's root mid-merge report names the continuation only for a
#   merge the continuation can land: a state file with MERGE_HEAD and a full
#   briefing. A checkout-cleared merge, or a marker an interrupted preparation
#   left, is sent to /gitlore:resolve.
# - A tier's position line that names an act rides both channels (D59).
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start
load helpers/merge-memory

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

# A head-vs-live merge prepared by the standalone resolver, the merger's
# synthesis staged, then MERGE_HEAD cleared by a checkout that keeps the index.
# Leaves $pending and $statefile.
checkout_cleared_staged_merge() {
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  pending=$(git -C memory rev-parse refs/gitlore/pending)
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  echo "synthesized" > memory/SYNTH.md
  git -C memory add -A
  git -C memory checkout -q --detach HEAD
  # The shape under test, so nothing below passes vacuously.
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD || true)" ]
  run ! git -C memory diff-index --quiet --cached HEAD --
  [ -f "$statefile" ]
}

# Run SessionStart; $sys and $ctx are the two channels.
session_start_over_store() {
  enable_gitlore
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  sys=$(jq -r '.systemMessage // ""' <<<"$output")
  ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$output")
}

# --- (a) the continuation over a checkout-cleared merge ------------------------

@test "continue-after-merge over a checkout-cleared merge commits nothing and keeps the pending side" {
  checkout_cleared_staged_merge
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -ne 0 ] || {
    printf 'the continuation exited 0 over a merge with no MERGE_HEAD; HEAD %s parents: %s\n' \
      "$(git -C memory rev-parse HEAD)" "$(git -C memory rev-list --parents -n 1 HEAD)" >&2
    return 1
  }
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
  [ "$(git -C memory rev-parse refs/gitlore/pending)" = "$pending" ]
  [ -f "$statefile" ]
  git -C memory diff --cached --name-only | grep -qx 'SYNTH.md'
  [[ "$stderr" == *"/gitlore:resolve"* ]]
}

@test "after the refusal, /gitlore:resolve restores the merge and the continuation lands it with both parents" {
  checkout_cleared_staged_merge
  live_before=$(git -C memory rev-parse live)
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -ne 0 ]
  run --separate-stderr bash "$RESOLVE"
  [[ "$output$stderr" == *"continue-after-merge"* ]]
  [ "$(git -C memory rev-parse MERGE_HEAD)" = "$pending" ]
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD^1)" = "$live_before" ]
  [ "$(git -C memory rev-parse HEAD^2)" = "$pending" ]
}

# --- (b) SessionStart over a merge the continuation cannot land ----------------

root_merge_prepared_against_remote() {
  wire_memory_remote
  printf 'local only\n' > memory/local-only.md
  git -C memory add local-only.md
  git -C memory commit -qm "a root-only fact"
  git -C memory push -q . HEAD:refs/heads/live
  push_memory_fact
  run bash "$CMD"
  [ "$status" -ne 0 ]
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
}

@test "SessionStart over a root merge whose MERGE_HEAD a checkout cleared sends it to /gitlore:resolve, not the continuation" {
  root_merge_prepared_against_remote
  git -C memory checkout -q --detach
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD || true)" ]
  session_start_over_store
  [[ "$ctx" == *"/gitlore:resolve"* ]] || {
    printf 'the agent is not sent to /gitlore:resolve; additionalContext:\n%s\n' "$ctx" >&2
    return 1
  }
  [[ "$ctx" != *"continue-after-merge"* ]]
  [[ "$ctx" != *"memory-merger"* ]]
  [[ "$sys" == *"/gitlore:resolve"* ]]
  [[ "$sys" != *"continue-after-merge"* ]]
  # The abort still applies to this shape (D81).
  [[ "$ctx" == *"abort-merge"* ]]
}

@test "SessionStart over a root merge whose preparation died before its briefing sends it to /gitlore:resolve" {
  root_merge_prepared_against_remote
  # The marker gitlore_write_merge_marker leaves: no changed_files, no briefing.
  jq '{flavor, store, source_ref, target_ref, continuation, publish}' "$statefile" > "$statefile.new"
  mv "$statefile.new" "$statefile"
  run jq -e 'has("changed_files")' "$statefile"
  [ "$status" -ne 0 ]
  session_start_over_store
  [[ "$ctx" == *"/gitlore:resolve"* ]] || {
    printf 'the agent is not sent to /gitlore:resolve; additionalContext:\n%s\n' "$ctx" >&2
    return 1
  }
  [[ "$ctx" != *"continue-after-merge"* ]]
  [[ "$ctx" != *"memory-merger"* ]]
}

@test "SessionStart over a fully prepared root merge still names the continuation" {
  root_merge_prepared_against_remote
  session_start_over_store
  [[ "$ctx" == *"continue-after-merge"* ]]
  [[ "$ctx" == *"memory-merger"* ]]
}

# --- (c) a tier's act-naming position line reaches the agent -------------------

tier_store() {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  commit_memory_state "memory: activate the tier"
  git -C memory push -q . HEAD:refs/heads/live
}

@test "a tier ahead of its remote hints /gitlore:push on the agent's channel too" {
  tier_store
  git -C memory/ddaanet commit -q --allow-empty -m "local, unpublished"
  git -C memory/ddaanet push -q . HEAD:refs/heads/live
  git -C memory add ddaanet
  git -C memory commit -q -m "record the tier commit"
  git -C memory push -q . HEAD:refs/heads/live
  session_start_over_store
  [[ "$sys" == *"tier 'ddaanet'"*"/gitlore:push"* ]]
  printf '%s\n' "$ctx" | grep -F "tier 'ddaanet'" | grep -qF '/gitlore:push' || {
    printf 'the agent is not told the tier has commits to publish; additionalContext:\n%s\n' "$ctx" >&2
    return 1
  }
}

@test "a tier in sync says so to the user only" {
  tier_store
  session_start_over_store
  [[ "$sys" == *"tier 'ddaanet' in sync."* ]]
  [[ "$ctx" != *"tier 'ddaanet' in sync."* ]]
}
