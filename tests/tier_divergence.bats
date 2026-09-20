#!/usr/bin/env bats
# One merge policy at every level (D17). Memory and each mounted tier are
# separate repositories with the same two gates — the pending commit against the
# store's own local `live`, and local `live` against the store's own remote — and
# either gate resolves the same way: prepare the merge, yield, let
# /gitlore:resolve land it.
#
# What made a tier different was not the policy but the continuation: it derived
# its store from `gitlore_memory_path`, so a merge prepared in a tier would have
# been committed in memory. The store now travels in the state file.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/tier-divergence

# --- store enumeration ---

@test "gitlore_memory_stores lists memory first, then each mounted tier" {
  make_parent_with_memory
  mount_tier_at_live ddaanet

  run gitlore_memory_stores memory
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "memory" ]
  [ "${lines[1]}" = "memory/ddaanet" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "an unmounted tier is not a store — git -C would escape to memory" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  rm -rf memory/ddaanet

  run gitlore_memory_stores memory
  [ "$status" -eq 0 ]
  [ "$output" = "memory" ]
}

@test "a repo with no tiers has exactly one store" {
  make_parent_with_memory
  run gitlore_memory_stores memory
  [ "$output" = "memory" ]
}

# --- the state file carries its store ---

@test "the merge state file records the store it belongs to, absolutely" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet

  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]

  statefile=$(tier_state_file ddaanet)
  [ -f "$statefile" ]
  store=$(jq -r .store "$statefile")
  [ "$store" = "$(cd memory/ddaanet && pwd)" ]
  # Absolute, so a continuation invoked from anywhere still finds it.
  case "$store" in /*) ;; *) return 1 ;; esac
}

@test "a tier merge lands in the TIER's gitdir, leaving memory's state clean" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet

  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  [ -f "$(tier_state_file ddaanet)" ]
  [ ! -f "$(gitlore_merge_state_file memory)" ]
}

@test "gitlore_stores_with_merge_state finds a merge prepared in a tier" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet
  bash "$PRE_PUSH" || true

  run gitlore_stores_with_merge_state memory
  [ "$status" -eq 0 ]
  [ "$output" = "memory/ddaanet" ]
}

# --- both gates yield, at both levels ---

@test "pre-push prepares a merge when a tier diverged from its remote" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet

  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  all="${output}${stderr}"
  # The trigger phrase commands/resolve.md matches on, plus the store, so a tier
  # merge is distinguishable from a memory one in the same output.
  [[ "$all" == *"gitlore: memory merge prepared"* ]]
  [[ "$all" == *"head-vs-remote"* ]]
  [[ "$all" == *"memory/ddaanet"* ]]
  # The old behaviour was to report and stop, and the state file is what tells
  # the two apart: a merge was actually prepared, not just announced.
  [ -f "$(tier_state_file ddaanet)" ]
}

@test "pre-commit prepares a merge when a tier commit diverged from its own live" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  # `live` moves sideways underneath the detached worktree.
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  all="${output}${stderr}"
  [[ "$all" == *"gitlore: memory merge prepared"* ]]
  [[ "$all" == *"head-vs-live"* ]]
  [ -f "$(tier_state_file ddaanet)" ]
}

@test "a tier push failure that is not divergence is not sent to a merge" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  # Reachable remote, refused for a reason a merge cannot fix.
  rm -rf "$TMP_REPO/.bare-ddaanet.git/hooks"
  mkdir -p "$TMP_REPO/.bare-ddaanet.git/hooks"
  printf '#!/bin/sh\nexit 1\n' > "$TMP_REPO/.bare-ddaanet.git/hooks/pre-receive"
  chmod +x "$TMP_REPO/.bare-ddaanet.git/hooks/pre-receive"

  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  all="${output}${stderr}"
  [[ "$all" == *"not because of divergence"* ]]
  [ ! -f "$(tier_state_file ddaanet)" ]
}

@test "the standalone resolver publishes no memory pointer ahead of a tier it could not publish" {
  # Memory's commit records the tier's, so memory going out first would leave
  # a colleague fetching a gitlink the tier remote cannot resolve (D17).
  make_parent_with_memory
  git -C memory push -q origin live
  mount_tier_at_live ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  git -C memory merge-base --is-ancestor origin/live live
  [ "$(git -C memory rev-parse live)" != "$(git -C memory rev-parse origin/live)" ]
  published=$(git --git-dir="$TMP_REPO/.bare-memory.git" rev-parse live)
  printf '#!/bin/sh\necho "declined by policy" >&2\nexit 1\n' > "$TMP_REPO/.bare-ddaanet.git/hooks/pre-receive"
  chmod +x "$TMP_REPO/.bare-ddaanet.git/hooks/pre-receive"

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"declined by policy"* ]]
  [ "$(git --git-dir="$TMP_REPO/.bare-memory.git" rev-parse live)" = "$published" ]
}

# --- a prepared merge must survive the next session start ---

# A prepared merge leaves the tier detached AT live with the merge staged, and a
# clean auto-merge stages no unmerged entries — so SessionStart's tier re-detach
# had nothing to refuse over: `checkout --detach live` succeeded on the commit
# HEAD was already on and `remove_branch_state()` unlinked MERGE_HEAD/MERGE_MSG.
# The state file then survives without MERGE_HEAD. The stale-state guard can
# repair that (tests/resolve_recovery.bats), but the repair reads the index to
# decide how, so a session start that provokes the damage every time is what
# turns a recovery path into the normal one. Cleanliness is what makes it bite,
# so the fixture must merge cleanly — the two sides touch different files.
@test "SessionStart leaves a tier's prepared merge intact instead of re-detaching over it" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT" || true
  merge_head=$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)
  [ -n "$merge_head" ]
  [ -f "$(git -C memory/ddaanet rev-parse --git-path MERGE_MSG)" ]
  [ -f "$(tier_state_file ddaanet)" ]

  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]

  [ "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" = "$merge_head" ]
  [ -f "$(git -C memory/ddaanet rev-parse --git-path MERGE_MSG)" ]
  # And the skipped re-detach is reported, not silent: an untouched tier that
  # says nothing is indistinguishable from one that synced.
  echo "$output" | jq -e '.systemMessage | test("tier .ddaanet. has an unfinished merge")'
  echo "$output" | jq -e '.systemMessage | test("/gitlore:resolve")'
  # On BOTH channels: systemMessage is user-only (D14), and the acts that would
  # destroy the merge — check out, reset, commit into — are the agent's to take.
  # Matched on the whole phrase, not on the tier path alone: this store also has
  # a dangling pointer, and its report names "memory/ddaanet/MEMORY.md", so a
  # bare path match passes with no guard context emitted at all.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("memory/ddaanet holds an unfinished merge")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("Do not check it out, reset it, or commit into it")'
}

# A mid-merge tier is skipped by the pin loop above and then met again by the
# compose that follows: the tier's own commit moved it off the gitlink memory
# records, so rule 7 refuses the pass (D36). Refusing is right — projecting
# root's index onto a carrier holding a staged merge would dirty the merge — so
# what has to hold is that the two notices agree about the remedy.
@test "SessionStart's compose refuses a mid-merge tier with the same remedy the pin loop gave" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT" || true
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]

  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]

  echo "$output" | jq -e '.systemMessage | test("tier .ddaanet. has an unfinished merge")'
  echo "$output" | jq -e '.systemMessage | test("tier composition refused")'
  echo "$output" | jq -e '.systemMessage | test("tier .ddaanet. is mid-merge")'
  # One remedy on the whole message, not two contradictory ones: the
  # return-to-the-pin checkout would unlink MERGE_HEAD and lose the merge.
  echo "$output" | jq -e '.systemMessage | test("checkout --detach") | not'
}
