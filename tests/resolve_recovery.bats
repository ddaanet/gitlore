#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"
PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}
teardown() { teardown_tmp_repo; }

@test "recovery: a prepared merge met by a later gate is continued, not discarded" {
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  statefile=$(gitlore_merge_state_file memory)
  pending=$(git -C memory rev-parse "$GITLORE_PENDING_REF")
  # What the merger sub-agent staged before the session ended: a file no
  # auto-merge of the two sides produces, so its survival is unambiguous.
  printf 'synthesized by the merger\n' > memory/SYNTH.md
  git -C memory add -A
  state_before=$(cat "$statefile")

  # A gate meeting the prepared merge in a later session.
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  all="$output$stderr"
  [[ "$all" == *"continue-after-merge"* ]]
  # Everything the sub-agent would resume from is exactly where it left it.
  [ "$(git -C memory rev-parse MERGE_HEAD)" = "$pending" ]
  git -C memory diff --cached --name-only | grep -qx 'SYNTH.md'
  [ "$(cat "$statefile")" = "$state_before" ]
  [ "$(git -C memory rev-parse "$GITLORE_PENDING_REF")" = "$pending" ]
}

@test "recovery: /gitlore:resolve continues a prepared merge rather than re-preparing it" {
  # The skill's standalone entry: no directive reached an agent, so the script
  # is run bare. It needs a remote carrying `live` to get past its early
  # repairs and reach the stale-state guard.
  git -C memory push -q origin live
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  pending=$(git -C memory rev-parse "$GITLORE_PENDING_REF")
  printf 'synthesized by the merger\n' > memory/SYNTH.md
  git -C memory add -A

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  all="$output$stderr"
  [[ "$all" == *"continue-after-merge"* ]]
  [ "$(git -C memory rev-parse MERGE_HEAD)" = "$pending" ]
  git -C memory diff --cached --name-only | grep -qx 'SYNTH.md'
}

@test "recovery: a merge prepared in an earlier session lands through the continuation" {
  git -C memory push -q origin live
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  live_before=$(git -C memory rev-parse live)
  pending=$(git -C memory rev-parse "$GITLORE_PENDING_REF")
  printf 'synthesized by the merger\n' > memory/SYNTH.md
  git -C memory add -A

  run --separate-stderr bash "$PRE_COMMIT"
  [[ "$output$stderr" == *"continue-after-merge"* ]]
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]

  merge_commit=$(git -C memory rev-parse HEAD)
  # The authority is still the first parent (D6) and the pending commit the
  # second, so the session boundary changed nothing about what landed.
  [ "$(git -C memory rev-parse "${merge_commit}^1")" = "$live_before" ]
  [ "$(git -C memory rev-parse "${merge_commit}^2")" = "$pending" ]
  [ "$merge_commit" = "$(git -C memory rev-parse live)" ]
  git -C memory cat-file -e "$merge_commit:SYNTH.md"
  [ ! -f "$(gitlore_merge_state_file memory)" ]
  run git -C memory rev-parse -q --verify "$GITLORE_PENDING_REF"
  [ "$status" -ne 0 ]
}

@test "recovery: a merge that never started is reported, not announced as prepared" {
  # The merge's own output is discarded on purpose — a conflict is the expected
  # outcome and the conflicted worktree IS the deliverable. But a merge that
  # never started leaves no MERGE_HEAD, and without checking for it the caller
  # would write a state file and dispatch a sub-agent to resolve nothing.
  # Reproduced here with an authority HEAD already contains, which is now
  # recognized by ancestry BEFORE the detach that used to make this diagnosis
  # move HEAD — so the report names the state rather than relaying git's
  # "Already up to date" from a checkout already performed.
  before=$(git -C memory rev-parse HEAD)
  run --separate-stderr gitlore_prepare_merge memory live HEAD
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"already contains HEAD"* ]]
  run git -C memory rev-parse -q --verify MERGE_HEAD
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
}

@test "recovery: orphaned MERGE_HEAD with no state file is flagged, not reported clean" {
  make_diverged_head_vs_live memory
  # Simulate an interrupted gitlore_prepare_merge: it stages a real merge
  # (MERGE_HEAD set, content staged) but the caller dies before
  # gitlore_write_merge_state runs — the exact edify incident this guards.
  run --separate-stderr gitlore_prepare_merge memory live HEAD
  [ "$status" -eq 0 ]
  mh=$(git -C memory rev-parse -q --verify MERGE_HEAD)
  [ -n "$mh" ]
  [ ! -f "$(gitlore_merge_state_file memory)" ]

  run gitlore_detect_stale_merge_state memory
  [ "$output" = "orphaned-merge-head" ]

  run --separate-stderr gitlore_guard_stale_merge_state memory
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"manual intervention"* ]]
  [[ "$output$stderr" == *"$mh"* ]]
}

# --- a merge whose MERGE_HEAD a checkout cleared ---
#
# `git checkout` — including the no-op re-checkout `submodule update` runs —
# calls remove_branch_state(), which unlinks MERGE_HEAD and MERGE_MSG silently
# while leaving the staged merge result in the index. A clean auto-merge has no
# unmerged entries for checkout to refuse over, so the state file outlives its
# own discriminator. What can be recovered depends on what the store holds, and
# every branch below is decided mechanically (D7).

@test "recovery: a checkout-cleared merge that nothing landed is discarded, and the gate re-prepares it" {
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  pending=$(git -C memory rev-parse "$GITLORE_PENDING_REF")
  # The shape a hand-run `git merge --abort` leaves: the pointers go and the
  # index is reset to HEAD, so nothing of the merge survives but gitlore's own
  # files. This is what a user asking to revert to the pre-merge state gets.
  git -C memory merge --abort
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD || true)" ]

  run --separate-stderr bash "$PRE_COMMIT"
  all="$output$stderr"
  # It says what it disposed of before it re-prepares, so a repair is never a
  # silent rewrite of the store.
  [[ "$all" == *"nothing landed"* ]]
  [[ "$all" == *"leftover state is discarded"* ]]
  [[ "$all" == *"memory merge prepared"* ]]
  # The divergent commit is not orphaned by the disposal: the merge the gate
  # just prepared is the same one, against the same pending side.
  [ "$(jq -r .source_ref "$(gitlore_merge_state_file memory)")" = "$pending" ]
}

@test "recovery: /gitlore:resolve repairs a checkout-cleared merge instead of refusing over it" {
  # The skill's own script walks the same guard every gate does, so a state it
  # could not touch made the documented repair path the one place a user could
  # not be sent. Push live first, or the default mode takes its "remote has no
  # live branch" early return before reaching the guard.
  git -C memory push -q origin live
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  git -C memory merge --abort

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  # Reaching the divergence again IS the repair: the script gets past the stale
  # state and prepares the merge the store still needs.
  [[ "$output$stderr" == *"memory merge prepared"* ]]
}

@test "recovery: a checkout-cleared merge with its synthesis staged keeps it and asks for the sub-agent" {
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  pending=$(git -C memory rev-parse "$GITLORE_PENDING_REF")
  # The merger sub-agent's synthesis, staged exactly as it leaves it.
  echo "synthesized" > memory/SYNTH.md
  git -C memory add -A
  git -C memory checkout -q --detach HEAD
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD || true)" ]

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [ "$(git -C memory rev-parse -q --verify MERGE_HEAD)" = "$pending" ]
  [ -f "$(git -C memory rev-parse --git-path MERGE_MSG)" ]
  [[ "$all" == *"memory merge prepared"* ]]
  [[ "$all" == *"continue-after-merge"* ]]
  # The staged synthesis survives: nothing aborted the merge out from under it.
  run git -C memory diff --cached --name-only
  [[ "$output" == *"SYNTH.md"* ]]
}

@test "recovery: a merge that landed before the checkout is restored, not declared dead" {
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  # Land the merge as the continuation does, then let a checkout move HEAD off
  # it while the state file is still there.
  GITLORE_MEMORY_COMMIT=1 git -C memory commit -q --no-edit
  landed=$(git -C memory rev-parse HEAD)
  git -C memory checkout -q --detach live
  # The merge commit is reachable from no ref, and `fsck --unreachable` still
  # does not name it — reflog entries are reachability roots — so "is there an
  # unreachable commit" is the wrong question to ask about a landed merge.
  run git -C memory fsck --unreachable
  [[ "$output" != *"$landed"* ]]

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"$landed"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$landed" ]
  [ "$(git -C memory rev-parse live)" = "$landed" ]
  [ ! -f "$(gitlore_merge_state_file memory)" ]
  run git -C memory rev-parse -q --verify "$GITLORE_PENDING_REF"
  [ "$status" -ne 0 ]
}

@test "recovery: a checkout-cleared merge whose HEAD is not the authority names both shas" {
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  head_at=$(git -C memory rev-parse HEAD)
  echo "synthesized" > memory/SYNTH.md
  git -C memory add -A
  git -C memory checkout -q --detach HEAD
  # `live` moves under the prepared merge, so the authority the state file names
  # is no longer the commit the merge was built on.
  advance_branch_with_file memory live MOVED.md moved "live moved on" live
  moved=$(git -C memory rev-parse live)

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [[ "$all" == *"$head_at"* ]]
  [[ "$all" == *"$moved"* ]]
  # Nothing was guessed at: the staged tree and the state file are as they were.
  [ -f "$(gitlore_merge_state_file memory)" ]
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD || true)" ]
}

@test "recovery: a stale merge state naming no pending commit is reported, not guessed at" {
  printf '{"flavor":"head-vs-live","store":"%s"}\n' "$(cd memory && pwd)" \
    > "$(gitlore_merge_state_file memory)"

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [[ "$all" == *"manual intervention required"* ]]
  # It says WHY it cannot classify: neither handle on the pending side is there.
  [[ "$all" == *"$GITLORE_PENDING_REF"* ]]
  [[ "$all" == *"source_ref"* ]]
  [ -f "$(gitlore_merge_state_file memory)" ]
}
