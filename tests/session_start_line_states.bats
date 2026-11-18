#!/usr/bin/env bats
# The session-start line (contract: one session-start line) over the states
# session_start_line.bats leaves open: where each count is measured from, a tier
# ahead or behind, the command when the stores disagree, unreachable beside a
# command, and the stores left out of the line, which keep their own messages.
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
load helpers/take-order
load helpers/unresolvable-pin

load helpers/session-line

# A hanging transport's sleepers are reaped here (make_hanging_remote).
teardown() {
  local pid
  if [ -f "$BATS_TEST_TMPDIR/hang.pids" ]; then
    while IFS= read -r pid || [ -n "$pid" ]; do
      # A dead pid is the expected case here; kill -0 is the probe.
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then kill "$pid"; fi
    done < "$BATS_TEST_TMPDIR/hang.pids"
  fi
  teardown_tmp_repo
}

memory_remote_live() { git --git-dir="$MEMORY_REMOTE" rev-parse live; }

# A tier commit on HEAD only, recorded by memory with memory published, so the
# pin keeps the tier where it is and memory stays level with its remote.
tier_head_commit_recorded() {
  git -C memory/ddaanet -c user.email=t@t -c user.name=t commit -q --allow-empty -m "${1:-tier head fact}"
  commit_memory_state "memory: record the tier commit"
  git -C memory push -q . HEAD:refs/heads/live
  git -C memory push -q origin live
}

# --- where N is measured from -------------------------------------------------------

@test "memory behind: N counts the remote commits HEAD lacks, not those live lacks" {
  synced_store
  advance_memory_live 1
  git -C memory push -q origin live
  push_remote_commits 2
  git -C memory fetch -q origin live
  [ "$(count memory HEAD..origin/live)" = 3 ]
  [ "$(count memory live..origin/live)" = 2 ]
  session_start
  assert_line "gitlore: Run /gitlore:merge (memory 3 behind; ddaanet in sync)"
  assert_no_old_lines
}

@test "memory whose HEAD is at the remote with live lagging: N counts what live lacks, never 0" {
  synced_store
  push_remote_commits 2
  git -C memory fetch -q origin live
  git -C memory checkout -q --detach origin/live
  [ "$(count memory live..HEAD)" = 2 ]
  [ "$(git -C memory rev-parse HEAD)" = "$(memory_remote_live)" ]
  session_start
  assert_line "gitlore: Run /gitlore:merge (memory 2 behind; ddaanet in sync)"
  assert_no_old_lines
}

@test "memory ahead with HEAD past live: N counts from HEAD" {
  synced_store
  commit_on_head_and_live
  git -C memory -c user.email=t@t -c user.name=t commit -q --allow-empty -m "head only 1"
  git -C memory -c user.email=t@t -c user.name=t commit -q --allow-empty -m "head only 2"
  [ "$(count memory "$(memory_remote_live)..HEAD")" = 3 ]
  [ "$(count memory "$(memory_remote_live)..live")" = 1 ]
  session_start
  assert_line "gitlore: Run /gitlore:push (memory 3 ahead; ddaanet in sync)"
  assert_no_old_lines
}

@test "memory ahead with live past HEAD: N counts from live" {
  synced_store
  commit_on_head_and_live
  advance_memory_live 2
  [ "$(count memory "$(memory_remote_live)..live")" = 3 ]
  [ "$(count memory "$(memory_remote_live)..HEAD")" = 1 ]
  session_start
  assert_line "gitlore: Run /gitlore:push (memory 3 ahead; ddaanet in sync)"
  assert_no_old_lines
}

@test "a tier whose live is past its remote and past HEAD reads N ahead from live" {
  synced_store
  tier_head_commit_recorded
  git -C memory/ddaanet push -q . HEAD:refs/heads/live
  advance_branch_with_file memory/ddaanet live a.md a "tier live 1"
  advance_branch_with_file memory/ddaanet live b.md b "tier live 2"
  [ "$(count memory/ddaanet "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)..live")" = 3 ]
  [ "$(count memory/ddaanet HEAD..live)" = 2 ]
  session_start
  assert_line "gitlore: Run /gitlore:push (memory in sync; ddaanet 3 ahead)"
  assert_no_old_lines
}

@test "a tier whose HEAD is past a live level with its remote reads N ahead from HEAD" {
  synced_store
  git -C memory/ddaanet -c user.email=t@t -c user.name=t commit -q --allow-empty -m "tier head 1"
  tier_head_commit_recorded "tier head 2"
  [ "$(count memory/ddaanet live..HEAD)" = 2 ]
  assert_level_with_remotes ddaanet
  session_start
  assert_line "gitlore: Run /gitlore:push (memory in sync; ddaanet 2 ahead)"
  assert_no_old_lines
}

@test "a tier whose remote is past live, live past HEAD, reads N behind from HEAD" {
  synced_store
  advance_tier_live 1
  push_tier_fact ddaanet "- [u1](u1.md) — one" >/dev/null
  push_tier_fact ddaanet "- [u2](u2.md) — two" >/dev/null
  git -C memory/ddaanet fetch -q origin live
  [ "$(count memory/ddaanet HEAD..FETCH_HEAD)" = 3 ]
  [ "$(count memory/ddaanet live..FETCH_HEAD)" = 2 ]
  session_start
  assert_line "gitlore: Run /gitlore:merge (memory in sync; ddaanet 3 behind)"
  assert_no_old_lines
}

# --- the command across stores -------------------------------------------------------

@test "memory behind and a tier ahead: push, whichever store comes first" {
  synced_store
  tier_head_commit_recorded
  push_remote_commits 2
  git -C memory fetch -q origin live
  [ "$(count memory live..origin/live)" = 2 ]
  [ "$(count memory/ddaanet live..HEAD)" = 1 ]
  session_start
  assert_line "gitlore: Run /gitlore:push (memory 2 behind; ddaanet 1 ahead)"
  assert_no_old_lines
  assert_absent '/gitlore:merge'
}

@test "memory diverged from its remote reads diverged: push" {
  synced_store
  commit_on_head_and_live
  push_remote_commits 1
  git -C memory fetch -q origin live
  run ! git -C memory merge-base --is-ancestor live origin/live
  run ! git -C memory merge-base --is-ancestor origin/live live
  session_start
  assert_line "gitlore: Run /gitlore:push (memory diverged; ddaanet in sync)"
  assert_no_old_lines
}

@test "a tier whose HEAD forked from its local live reads diverged: push" {
  synced_store
  tier_head_commit_recorded
  advance_branch_with_file memory/ddaanet live side.md side "tier live side"
  run ! git -C memory/ddaanet merge-base --is-ancestor live HEAD
  run ! git -C memory/ddaanet merge-base --is-ancestor HEAD live
  session_start
  assert_line "gitlore: Run /gitlore:push (memory in sync; ddaanet diverged)"
  assert_no_old_lines
}

@test "an unreachable memory leaves the command to the tier behind: merge" {
  synced_store
  advance_tier_live 2
  git -C memory remote set-url origin "$TMP_REPO/no-such-remote.git"
  session_start
  assert_line "gitlore: Run /gitlore:merge (memory unreachable; ddaanet 2 behind)"
  assert_no_old_lines
  assert_present sys "could not fetch memory's remote"
}

@test "a tier that is locally ahead and unreachable reads unreachable and contributes no push" {
  synced_store
  tier_head_commit_recorded
  [ "$(count memory/ddaanet live..HEAD)" = 1 ]
  mv "$TMP_REPO/.bare-ddaanet.git" "$TMP_REPO/.bare-ddaanet.git.gone"
  session_start
  assert_line "gitlore: memory in sync; ddaanet unreachable"
  assert_no_old_lines
  assert_present sys "tier 'ddaanet' could not fetch from its remote"
  assert_absent '/gitlore:push'
}

@test "a tier whose fetch times out reads unreachable, after the timeout message" {
  synced_store
  # shellcheck disable=SC2034 # read by make_hanging_remote (tests/helpers/session-line.bash)
  HANG_SECONDS=30 HANG_PIDS="$BATS_TEST_TMPDIR/hang.pids"
  # A bound memory's healthy fetch of its local remote meets under load.
  export GITLORE_FETCH_TIMEOUT=5
  make_hanging_remote memory/ddaanet
  session_start
  assert_line "gitlore: memory in sync; ddaanet unreachable"
  assert_no_old_lines
  assert_present sys "tier 'ddaanet' could not fetch from its remote \\(timed out after 5s\\)"
  [ "$(offset sys "timed out after 5s")" -lt "$(offset sys 'gitlore: memory in sync; ddaanet unreachable')" ]
}

@test "a tier remote with no live is not unreachable: it reads against local live" {
  synced_store
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" update-ref -d refs/heads/live
  run ! git -C memory/ddaanet ls-remote --exit-code origin refs/heads/live
  session_start
  assert_line "gitlore: memory in sync; ddaanet in sync"
  assert_no_old_lines
  assert_absent 'could not fetch'
}

# --- memory dirty, lost pins ----------------------------------------------------------

@test "memory behind and dirty is listed N behind and keeps its uncommitted-changes message" {
  synced_store
  advance_memory_live 2
  git -C memory push -q origin live
  printf 'draft\n' > memory/draft.md
  [ "$(count memory HEAD..live)" = 2 ]
  [ -n "$(git -C memory status --porcelain)" ]
  session_start
  assert_line "gitlore: Run /gitlore:merge (memory 2 behind; ddaanet in sync)"
  assert_no_old_lines
  assert_present sys '^gitlore: memory — uncommitted changes present\.$'
  assert_present ctx '^gitlore: memory — uncommitted changes present\.$'
}

@test "memory whose parent pin nobody holds keeps the pin report and is still listed" {
  parent_pin_nobody_holds
  session_start
  assert_line "gitlore: memory in sync"
  assert_no_old_lines
  sys_has "${lost:0:12}" 'merged upstream'
  ctx_has "${lost:0:12}" 'merged upstream'
}

@test "a tier whose recorded commit nobody holds keeps the pin report and is still listed" {
  tier_gitlink_nobody_holds
  session_start
  assert_line "gitlore: memory in sync; ddaanet in sync"
  assert_no_old_lines
  sys_has "${lost:0:12}" '/gitlore:push'
  ctx_has "${lost:0:12}" '/gitlore:push'
}

# --- stores left out ----------------------------------------------------------------

@test "a tier that could not be checked out is absent from the line and keeps its notices" {
  synced_store
  unmaterialize_tier ddaanet
  session_start
  assert_line "gitlore: memory in sync"
  assert_no_old_lines
  assert_present sys "tier 'ddaanet' could not be checked out at its recorded commit"
  assert_present ctx "tier 'ddaanet' could not be checked out, so its facts"
}

@test "a diverged tier whose rewrite record cannot be fetched is absent from the line and keeps its message" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  rewrite_remote_history memory/ddaanet "$TMP_REPO/.bare-ddaanet.git"
  rewrite_position_clone memory/ddaanet old
  git -C memory add ddaanet
  git -C memory commit -q -m "record the tier commit"
  git -C memory update-ref refs/heads/live HEAD
  rewrite_break_record "$TMP_REPO/.bare-ddaanet.git"
  session_start
  assert_line "gitlore: memory in sync"
  assert_no_old_lines
  assert_present sys "tier 'ddaanet' has diverged from its remote 'live', and its rewrite record gitlore/rewrites could not be fetched"
  assert_absent '/gitlore:push'
}

@test "memory holding a merge gitlore did not prepare is absent from the line; the tier is listed" {
  synced_store
  git -C memory rev-parse HEAD > "$(git -C memory rev-parse --absolute-git-dir)/MERGE_HEAD"
  git -C memory rev-parse -q --verify MERGE_HEAD >/dev/null
  session_start
  assert_line "gitlore: ddaanet in sync"
  assert_no_old_lines
  assert_present sys 'memory holds a merge gitlore did not prepare'
  assert_present ctx 'memory holds a merge gitlore did not prepare'
}

# Green today by construction (no store prints a position here): a pin that the
# new code adds no line when it has nothing to list, not a red.
@test "pin: with every store left out no line is printed, and the kept message stands" {
  make_parent_with_memory
  rewrite_remote_history memory "$TMP_REPO/.bare-memory.git"
  rewrite_position_clone memory old
  rewrite_break_record "$TMP_REPO/.bare-memory.git"
  session_start
  assert_present sys "upstream memory's rewrite record gitlore/rewrites could not be fetched"
  assert_present ctx "upstream memory's rewrite record gitlore/rewrites could not be fetched"
  assert_no_line
  assert_no_old_lines
}
