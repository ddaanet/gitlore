#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# Assertions deliberately match the literal string `$CLAUDE_PLUGIN_ROOT` to prove
# it does NOT leak unexpanded; the single quotes are intentional.
# shellcheck disable=SC2016
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  # Stage a parent-side change so the pre-commit hook has a real commit context.
  echo parent > parent-file
  git add parent-file
  make_diverged_head_vs_live memory
}
teardown() { teardown_tmp_repo; }

@test "head-vs-live: pre-commit yields directive on ff-push failure" {
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"flavor=head-vs-live"* ]]
  [[ "$output$stderr" == *"continue-after-merge"* ]]
  # Directive emits the absolute resolve.sh path AND a cd to the parent repo
  # (so the sub-agent's shell needs neither CLAUDE_PLUGIN_ROOT nor a particular CWD).
  # Dogfood-driven fix.
  [[ "$output$stderr" == *"cd \"$TMP_REPO\" && bash \"$PLUGIN_ROOT/scripts/resolve.sh\""* ]]
  [[ "$output$stderr" != *'$CLAUDE_PLUGIN_ROOT'* ]]
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "head-vs-live" ]
  # The authority is the merge target; the pending commit is the source.
  [ "$(jq -r .target_ref "$statefile")" = "live" ]
  [ "$(jq -r .continuation "$statefile")" = "continue-after-merge" ]
  # The pending commit is pinned so `merge --abort` cannot strand it (no branch
  # holds it under the detached model).
  [ "$(git -C memory rev-parse refs/gitlore/pending)" = "$(jq -r .source_ref "$statefile")" ]
  # changed_files must include BOTH sides of the merge (target_ref AND source_ref).
  # Pre-fix bug: only target-side (LIVE.md) made it in; source-side was lost.
  changed=$(jq -r '.changed_files[]' "$statefile" | sort | paste -sd, -)
  [ "$changed" = "HEAD_SIDE.md,LIVE.md" ]
}

# The directive's reader is the agent, and the harness above it carries a blanket
# "do not call the AgentTool unless the user requested it" that nothing in a repo
# can qualify. A directive that merely NAMES the sub-agent reads as an option, so
# the agent reports the blocker and stops -- which once stalled a release on a
# round trip. The text has to carry its own authorization instead: the git
# operation that triggered the merge IS the request for this dispatch. That
# argument is scoped to this dispatch and must stay visible in the text, so it
# never reads as licence to skip a permission gate in general.
@test "the merge directive authorizes the dispatch it asks for" {
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  local all="$output$stderr"
  # Plugin-qualified: a bare `memory-merger` fails discovery with
  # `Agent type not found`.
  [[ "$all" == *"gitlore:memory-merger"* ]]
  # The instruction, and the argument that licenses it.
  [[ "$all" == *"required step of the git operation"* ]]
  [[ "$all" == *"without asking first"* ]]
  # Approval still governs the merge the sub-agent proposes. Authorizing the
  # dispatch must not read as authorizing that too.
  [[ "$all" == *"on approval of its synthesis"* ]]
}

@test "head-vs-live loop: continuation yields again if retry-push fails" {
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  # The merge is prepared (HEAD detached at live, MERGE_HEAD set) but not
  # committed. Simulate a concurrent worktree advancing `live` underneath us
  # during synthesis. Because `live` is never checked out, this is a one-line
  # ref advance — under the old branch model it took a 20-line checkout dance.
  advance_branch_with_file memory live SIBLING.md sibling-advance "Sibling live advance"
  run_stub_synth memory || true
  # The continuation committed the merge, then `push . HEAD:live` was refused
  # (live now points at a commit the merge does not contain). Re-prepare fires.
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "head-vs-live" ]
}

@test "head-vs-live: continuation finalizes the merge, ff-pushes live, stays detached" {
  live_before=$(git -C memory rev-parse live)
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  run_stub_synth memory

  # HEAD stays detached and `live` lands on the merge commit.
  run git -C memory symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  merge_commit=$(git -C memory rev-parse HEAD)
  [ "$merge_commit" = "$(git -C memory rev-parse live)" ]
  # First-parent invariant (D6): the authoritative side (live before the merge)
  # is the first parent; the pending commit is the second.
  [ "$(git -C memory rev-parse "${merge_commit}^1")" = "$live_before" ]
  [ "$(git -C memory rev-parse "${merge_commit}^2")" != "$live_before" ]
  # Both sides' content landed.
  [ -f memory/LIVE.md ]
  [ -f memory/HEAD_SIDE.md ]
  # State file removed and the pending pin released.
  [ ! -f "$(git -C memory rev-parse --git-path gitlore-merge-state)" ]
  run git -C memory rev-parse --verify -q refs/gitlore/pending
  [ "$status" -ne 0 ]
}

