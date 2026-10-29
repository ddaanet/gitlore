#!/usr/bin/env bats
# The commit-trace check of the memory-commit and tier-write assertion scripts:
# the session transcript must show the gitlore:commit skill ahead of the
# gitlore-commit command. The end-state cases are in asserts_commit.bats; both
# suites share tests/helpers/eval-asserts.bash.

# bats runs each @test in a subshell; with `setup` in the shared helper,
# the linter reports the test-local `run` results as lost modifications.
# shellcheck disable=SC2030,SC2031
# shellcheck source=tests/helpers/eval-asserts.bash
source "$BATS_TEST_DIRNAME/../../helpers/eval-asserts.bash"

# ------------------------------------------------------- the commit trace
#
# The store gate is gone, so a raw `git -C memory commit` lands as easily as the
# skill's command. The session transcript is what tells them apart: the
# gitlore:commit skill is invoked first, then gitlore-commit runs. Both
# assertions grade the same trace, on a memory that did move.

@test "memory-commit: passes when the skill was invoked and gitlore-commit ran after it" {
  _make_dirty_approved_memory
  _commit_approved
  _run_assert memory-commit
  assert_ok
}

@test "memory-commit: passes when a probe mentioning gitlore-commit precedes the skill" {
  _make_dirty_approved_memory
  _commit_approved
  _write_commit_transcript "$_BASH_PROBE" "$_SKILL_COMMIT" "$_BASH_COMMIT"
  _run_assert memory-commit
  assert_ok
}

@test "memory-commit: fails when no transcript was captured" {
  _make_dirty_approved_memory
  _commit_approved
  rm -f "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert memory-commit
  assert_fails "no session transcript"
}

@test "memory-commit: fails when the commit ran without the gitlore:commit skill" {
  _make_dirty_approved_memory
  _commit_approved
  _write_commit_transcript "" "$_BASH_COMMIT"
  _run_assert memory-commit
  assert_fails "gitlore:commit skill was never invoked"
}

@test "memory-commit: fails when only another skill was invoked" {
  _make_dirty_approved_memory
  _commit_approved
  _write_commit_transcript "$_SKILL_WRITING" "$_BASH_COMMIT"
  _run_assert memory-commit
  assert_fails "gitlore:commit skill was never invoked"
}

# gitlore:memory-writing is the review directive's skill, run by the commit
# skill; it does not stand in for it.
@test "memory-commit: fails when the skill was invoked after the commit ran" {
  _make_dirty_approved_memory
  _commit_approved
  _write_commit_transcript "$_BASH_COMMIT" "$_SKILL_COMMIT"
  _run_assert memory-commit
  assert_fails "before the gitlore:commit skill"
}

@test "memory-commit: fails when memory moved by a raw git commit and gitlore-commit never ran" {
  _make_dirty_approved_memory
  _commit_approved
  _write_commit_transcript "$_SKILL_COMMIT" "$_BASH_RAW"
  _run_assert memory-commit
  assert_fails "gitlore-commit was never run"
}

@test "tier-write: fails when no transcript was captured" {
  _make_tier_write_end_state
  _commit_approved
  rm -f "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert tier-write
  assert_fails "no session transcript"
}

@test "tier-write: fails when the commit ran without the gitlore:commit skill" {
  _make_tier_write_end_state
  _commit_approved
  _write_commit_transcript "" "$_BASH_COMMIT"
  _run_assert tier-write
  assert_fails "gitlore:commit skill was never invoked"
}

@test "tier-write: fails when the skill was invoked after the commit ran" {
  _make_tier_write_end_state
  _commit_approved
  _write_commit_transcript "$_BASH_COMMIT" "$_SKILL_COMMIT"
  _run_assert tier-write
  assert_fails "before the gitlore:commit skill"
}

@test "tier-write: fails when memory moved by a raw git commit and gitlore-commit never ran" {
  _make_tier_write_end_state
  _commit_approved
  _write_commit_transcript "$_SKILL_COMMIT" "$_BASH_RAW"
  _run_assert tier-write
  assert_fails "gitlore-commit was never run"
}

# The order of the checks: a memory that never moved is reported as that, not
# as a missing trace.
@test "memory-commit: a memory that never moved is reported before the transcript is read" {
  _make_dirty_approved_memory
  _run_assert memory-commit
  assert_fails "memory never moved"
}

# The turn-1 snapshot is the absence-of-an-in-turn-commit check. It reads the
# runner's snapshot, so a transcript that looks right does not excuse it.
@test "memory-commit: a well-formed trace does not excuse a commit made before approval" {
  _make_dirty_approved_memory
  _commit_approved
  git -C "$EVAL_REPO/memory" rev-parse HEAD > "$EVAL_OUT_DIR/memory-after-turn1"
  _run_assert memory-commit
  assert_fails "before approval"
}
