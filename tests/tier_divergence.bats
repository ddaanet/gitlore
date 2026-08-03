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

PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"
PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"
RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"
SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

approve() { printf '%s\n' "$1" > "$(gitlore_commit_msg_file memory)"; }

mount_tier_at_live() {
  local tier="${1:-ddaanet}"
  make_tier_in_memory "$tier"
  git -C "memory/$tier" fetch -q origin "live:live"
  git -C "memory/$tier" checkout -q --detach live
}

# Commit a tier fact locally after someone else advanced the tier remote, which
# is the shape every remote-divergence case below needs.
diverge_tier_from_remote() {
  local tier="${1:-ddaanet}"
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  echo "- [org fact](f.md) — ours" >> "memory/$tier/MEMORY.md"
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  push_tier_fact "$tier" "- [their fact](t.md) — theirs" >/dev/null
}

tier_state_file() { git -C "memory/${1:-ddaanet}" rev-parse --git-path gitlore-merge-state; }

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

# --- a prepared merge must survive the next session start ---

# A prepared merge leaves the tier detached AT live with the merge staged, and a
# clean auto-merge stages no unmerged entries — so SessionStart's tier re-detach
# had nothing to refuse over: `checkout --detach live` succeeded on the commit
# HEAD was already on and `remove_branch_state()` unlinked MERGE_HEAD/MERGE_MSG.
# The state file then survived without MERGE_HEAD, which every guard reports as
# "manual intervention required": any merge that outlived one session was dead.
# Cleanliness is what makes it bite, so the fixture must merge cleanly — the
# two sides touch different files.
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
  # Memory itself was not committed into.
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
  [ ! -f "$(tier_state_file ddaanet)" ]
}

# The window between "merge landed" and "memory commit records it". The tier
# pass pins every tier unconditionally and on purpose (a clone made before tiers
# were pinned sits ahead already), and `submodule update` reads the gitlink from
# the superproject's INDEX — so the continuation staging the moved one is the
# only thing standing between a landed merge and a silent revert to the commit
# memory still records. Nothing reports the revert: /gitlore:merge exited 0, and
# the next session calls the tier synced.
@test "a landed tier merge survives the next SessionStart's unconditional pin" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet
  pinned=$(git -C memory rev-parse HEAD:ddaanet)
  bash "$PRE_PUSH" || true
  git -C memory/ddaanet add -A
  bash "$RESOLVE" continue-after-merge
  merged=$(git -C memory/ddaanet rev-parse HEAD)
  # The fixture has to give the pin something destructive to do: the tier is off
  # the commit memory records, and memory has NOT committed the move. Without
  # both, the pin is a no-op and this test passes with the staging deleted.
  [ "$merged" != "$pinned" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pinned" ]

  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]

  # Asserted against the commit, not a clean `git status` — the store is dirty
  # either way, so status passes in both worlds.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$merged" ]
  # And the merged content is what the revert would have taken back.
  grep -qF -- '- [org fact](f.md) — ours' memory/ddaanet/MEMORY.md
  grep -qF -- '- [their fact](t.md) — theirs' memory/ddaanet/MEMORY.md
}

@test "abort-then-retry aborts the tier's merge, not memory's" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet
  bash "$PRE_PUSH" || true
  [ -f "$(tier_state_file ddaanet)" ]

  # Re-entry detects the same divergence and prepares it again; what matters is
  # that the abort ran in the tier and left memory untouched.
  run bash "$RESOLVE" abort-then-retry
  [ -z "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD || true)" ] || \
    [ -f "$(tier_state_file ddaanet)" ]
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
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
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
