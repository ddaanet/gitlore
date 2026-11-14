#!/usr/bin/env bats
# The one instruction line SessionStart prints for every store (contract: one
# session-start line). Memory first, then the tiers in .gitmodules order, each
# with a position word (`in sync`, `N ahead`, `N behind`, `diverged`,
# `unreachable`); `Run /gitlore:push (...)` when a listed store is ahead or
# diverged, else `Run /gitlore:merge (...)` when one is behind, else the bare
# `gitlore: memory in sync; ddaanet in sync` form. Printed once on each channel
# (systemMessage and additionalContext, same text), after any fetch-failure
# message of the run. The per-store position lines it replaces are absent.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
# Run from outside tests/ (a scratch copy), PLUGIN_ROOT is the repository and
# the libraries setup.bash sources from it are sourced here; a no-op in tests/.
if [ ! -d "$PLUGIN_ROOT/scripts/lib" ]; then
  PLUGIN_ROOT=/Users/david/code/gitlore
  export PLUGIN_ROOT
  for f in "$PLUGIN_ROOT"/scripts/lib/*.sh; do
    # shellcheck disable=SC1090
    source "$f"
  done
fi
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start
load helpers/merge-memory
load helpers/rewrite-fixtures

load helpers/session-line

# --- in sync ----------------------------------------------------------------------

@test "memory and one tier in sync read the bare line with no command, on both channels" {
  synced_store
  session_start
  assert_line "gitlore: memory in sync; ddaanet in sync"
  assert_no_old_lines
  assert_absent '/gitlore:(push|merge|resolve)'
}

# --- one store off ----------------------------------------------------------------

@test "memory 2 commits ahead of its remote: push, with the count" {
  synced_store
  commit_on_head_and_live
  commit_on_head_and_live
  [ "$(git -C memory rev-list --count "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)..live")" = 2 ]
  session_start
  assert_line "gitlore: Run /gitlore:push (memory 2 ahead; ddaanet in sync)"
  assert_no_old_lines
}

@test "memory 2 commits behind its remote: merge, with the count" {
  synced_store
  push_remote_commits 2
  git -C memory fetch -q origin live
  [ "$(git -C memory rev-list --count live..origin/live)" = 2 ]
  session_start
  assert_line "gitlore: Run /gitlore:merge (memory 2 behind; ddaanet in sync)"
  assert_no_old_lines
}

@test "a tier diverged from its remote with memory in sync: push, memory listed in sync" {
  synced_store
  diverge_tier
  git -C memory push -q origin live
  [ "$(git -C memory rev-parse live)" = "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" ]
  session_start
  assert_line "gitlore: Run /gitlore:push (memory in sync; ddaanet diverged)"
  assert_no_old_lines
}

@test "memory whose HEAD forked from its local live reads diverged: push" {
  synced_store
  make_diverged_head_vs_live
  run ! git -C memory merge-base --is-ancestor live HEAD
  run ! git -C memory merge-base --is-ancestor HEAD live
  session_start
  assert_line "gitlore: Run /gitlore:push (memory diverged; ddaanet in sync)"
  assert_no_old_lines
}

@test "a tier whose local live equals origin/live and is 2 ahead of its HEAD reads 2 behind: merge" {
  synced_store
  advance_tier_live 2
  [ "$(git -C memory/ddaanet rev-parse live)" = "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" ]
  [ "$(git -C memory/ddaanet rev-list --count HEAD..live)" = 2 ]
  session_start
  assert_line "gitlore: Run /gitlore:merge (memory in sync; ddaanet 2 behind)"
  assert_no_old_lines
}

# --- several stores -----------------------------------------------------------------

@test "one store behind and another ahead: push wins and both words are listed" {
  synced_store
  commit_on_head_and_live
  advance_tier_live 2
  [ "$(git -C memory rev-list --count "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)..live")" = 1 ]
  [ "$(git -C memory/ddaanet rev-list --count HEAD..live)" = 2 ]
  session_start
  assert_line "gitlore: Run /gitlore:push (memory 1 ahead; ddaanet 2 behind)"
  assert_no_old_lines
  assert_absent '/gitlore:merge'
}

@test "two tiers are listed in .gitmodules order, not name or manifest order" {
  wire_memory_remote
  mount_tier_at_live zeta
  mount_tier_at_live alpha
  set_tier_manifest alpha zeta
  commit_memory_state "memory: activate the tiers"
  git -C memory push -q . HEAD:refs/heads/live
  git -C memory push -q origin live
  assert_level_with_remotes zeta
  assert_level_with_remotes alpha
  [ "$(git -C memory config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}' | tr '\n' ' ')" = "zeta alpha " ]
  session_start
  assert_line "gitlore: memory in sync; zeta in sync; alpha in sync"
  assert_no_old_lines
}

@test "the line appears once per channel when several stores need a command" {
  synced_store
  commit_on_head_and_live
  diverge_tier
  [ "$(count memory "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)..live")" = 2 ]
  [ "$(git -C memory rev-parse live)" = "$(git -C memory rev-parse HEAD)" ]
  session_start
  assert_line "gitlore: Run /gitlore:push (memory 2 ahead; ddaanet diverged)"
  assert_no_old_lines
  [ "$(count_match sys '/gitlore:push')" = 1 ]
  [ "$(count_match ctx '/gitlore:push')" = 1 ]
}

# --- unreachable --------------------------------------------------------------------

@test "a tier whose fetch fails reads unreachable, after its fetch-failure message, with no command" {
  synced_store
  mv "$TMP_REPO/.bare-ddaanet.git" "$TMP_REPO/.bare-ddaanet.git.gone"
  [ ! -e "$TMP_REPO/.bare-ddaanet.git" ]
  session_start
  assert_line "gitlore: memory in sync; ddaanet unreachable"
  assert_no_old_lines
  assert_present sys "tier 'ddaanet' could not fetch from its remote"
  [ "$(offset sys "tier 'ddaanet' could not fetch")" -ge 0 ]
  [ "$(offset sys "tier 'ddaanet' could not fetch")" -lt "$(offset sys 'gitlore: memory in sync; ddaanet unreachable')" ]
  [ "$(count_match ctx "tier 'ddaanet' could not fetch")" = 0 ]
  assert_absent '/gitlore:(push|merge)'
}

@test "memory whose fetch fails reads unreachable, after its fetch-failure message on both channels, with no command" {
  synced_store
  git -C memory remote set-url origin "$TMP_REPO/no-such-remote.git"
  session_start
  assert_line "gitlore: memory unreachable; ddaanet in sync"
  assert_no_old_lines
  assert_present sys "could not fetch memory's remote 'live'"
  assert_present ctx "could not fetch memory's remote 'live'"
  [ "$(offset sys "could not fetch memory's remote")" -ge 0 ]
  [ "$(offset sys "could not fetch memory's remote")" -lt "$(offset sys 'gitlore: memory unreachable')" ]
  [ "$(offset ctx "could not fetch memory's remote")" -ge 0 ]
  [ "$(offset ctx "could not fetch memory's remote")" -lt "$(offset ctx 'gitlore: memory unreachable')" ]
  assert_absent '/gitlore:(push|merge)'
}

@test "an unreachable store that is locally ahead still reads unreachable and contributes no push" {
  synced_store
  commit_on_head_and_live
  git -C memory -c user.email=t@t -c user.name=t commit -q --allow-empty -m "head only"
  run git -C memory merge-base --is-ancestor live HEAD
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse live)" != "$(git -C memory rev-parse HEAD)" ]
  git -C memory remote set-url origin "$TMP_REPO/no-such-remote.git"
  session_start
  assert_line "gitlore: memory unreachable; ddaanet in sync"
  assert_no_old_lines
  assert_present sys "could not fetch memory's remote"
  assert_absent '/gitlore:push'
}

# --- stores left out ----------------------------------------------------------------

@test "a tier with an unfinished merge is absent from the line, keeps its own message, and the others are listed" {
  wire_memory_remote
  mount_tier_at_live alpha
  mount_tier_at_live beta
  set_tier_manifest alpha beta
  commit_memory_state "memory: activate the tiers"
  git -C memory push -q . HEAD:refs/heads/live
  git -C memory push -q origin live
  git -C memory/beta rev-parse HEAD > "$(git -C memory/beta rev-parse --absolute-git-dir)/MERGE_HEAD"
  git -C memory/beta rev-parse -q --verify MERGE_HEAD >/dev/null
  session_start
  assert_line "gitlore: memory in sync; alpha in sync"
  assert_no_old_lines
  assert_present sys "tier 'beta' has an unfinished merge"
  assert_present ctx "holds an unfinished merge"
  assert_present sys '/gitlore:resolve'
}

@test "a diverged tier whose rewrite check hits is absent from the line and keeps its crossing message" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  rewrite_remote_history memory/ddaanet "$TMP_REPO/.bare-ddaanet.git"
  rewrite_position_clone memory/ddaanet old
  git -C memory add ddaanet
  git -C memory commit -q -m "record the tier commit"
  git -C memory update-ref refs/heads/live HEAD
  [ -n "$(git -C memory/ddaanet ls-remote origin refs/heads/gitlore/rewrites)" ]
  git -C memory/ddaanet fetch -q origin live
  run ! git -C memory/ddaanet merge-base --is-ancestor live FETCH_HEAD
  run ! git -C memory/ddaanet merge-base --is-ancestor FETCH_HEAD live
  session_start
  assert_line "gitlore: memory in sync"
  assert_no_old_lines
  assert_present sys 'cross-rewrite\.sh'
  assert_present ctx 'cross-rewrite\.sh'
  assert_absent '/gitlore:push'
}

# --- pending compose and the merge report -------------------------------------------

@test "a pending compose with a tier whose local live strictly contains HEAD prints neither D4 nor the compose report, and the line says merge" {
  composed_store
  make_compose_pending
  advance_tier_live 1
  [ "$(git -C memory/ddaanet rev-parse live)" = "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" ]
  run gitlore_live_ahead_of_head memory/ddaanet
  [ "$status" -eq 0 ]
  session_start
  assert_line "gitlore: Run /gitlore:merge (memory in sync; ddaanet 1 behind)"
  assert_no_old_lines
  assert_absent "these tiers hold commits on their local 'live'"
  assert_absent 'Run gitlore-compose'
  assert_absent 'a compose pass would change'
  assert_present sys '^gitlore: memory — uncommitted changes present\.$'
  assert_present ctx '^gitlore: memory — uncommitted changes present\.$'
}

@test "a pending compose with no such tier still prints the Run gitlore-compose report as its own message" {
  composed_store
  make_compose_pending
  run gitlore_live_ahead_of_head memory/ddaanet
  [ "$status" -ne 0 ]
  session_start
  assert_line "gitlore: memory in sync; ddaanet in sync"
  assert_no_old_lines
  assert_present sys 'a compose pass would change these indexes'
  assert_present ctx 'a compose pass would change these indexes'
  assert_present ctx 'Run gitlore-compose'
  assert_absent "these tiers hold commits on their local 'live'"
  assert_present sys '^gitlore: memory — uncommitted changes present\.$'
  assert_present ctx '^gitlore: memory — uncommitted changes present\.$'
}
