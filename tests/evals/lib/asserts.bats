#!/usr/bin/env bats
# The assertion scripts themselves, against end states built by hand.
# Covers the add-tier and recall assertions; tier-write and memory-commit are in
# asserts_commit.bats and share this suite's fixtures from
# tests/helpers/eval-asserts.bash.
#
# An assertion that always passes turns a scenario into an expensive no-op, and
# one that always fails blocks a release for nothing. Neither shows up when the
# eval runs — a green scenario looks the same either way — so each assertion is
# exercised here against a good end state and against the specific breakage it
# exists to catch.

# shellcheck source=tests/helpers/eval-asserts.bash
source "$BATS_TEST_DIRNAME/../../helpers/eval-asserts.bash"

# ------------------------------------------------------------------- add-tier

@test "add-tier: passes on a mounted, activated, composed tier" {
  _make_add_tier_end_state
  _run_assert add-tier
  assert_ok
}

@test "add-tier: fails when the intent file was never consumed" {
  _make_add_tier_end_state
  printf 'mode=mount\n' > "$EVAL_REPO/.claude/gitlore-add-tier"
  _run_assert add-tier
  assert_fails "never consumed it"
}

@test "add-tier: fails when the tier is mounted but not activated" {
  _make_add_tier_end_state
  : > "$EVAL_REPO/memory/.gitlore-tiers"
  _run_assert add-tier
  assert_fails "mounted but inactive"
}

@test "add-tier: fails when activation did not recompose the root index" {
  _make_add_tier_end_state
  printf '# Memory Index\n' > "$EVAL_REPO/memory/MEMORY.md"
  _run_assert add-tier
  assert_fails "composition did not run"
}

@test "add-tier: fails when the tier is left on a branch instead of detached at live" {
  _make_add_tier_end_state
  git -C "$EVAL_REPO/memory/acme" checkout -q -B main
  _run_assert add-tier
  assert_fails "not detached at live"
}

# The FR11 gate is the sole committer. A tier flow that commits inside memory
# would slip a change past the approval gate entirely.
@test "add-tier: fails when something committed inside the memory store" {
  _make_add_tier_end_state
  GITLORE_MEMORY_COMMIT=1 git -C "$EVAL_REPO/memory" commit -q -m "snuck in"
  _run_assert add-tier
  assert_fails "bypassing the FR11 gate"
}

@test "add-tier: fails when the tier was never mounted at all" {
  _make_memory
  printf 'acme\n' > "$EVAL_REPO/memory/.gitlore-tiers"
  _run_assert add-tier
  assert_fails "not checked out"
}

# --------------------------------------------------------------------- recall

_PROBE_CALL='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"./nightly-retry.sh"}}]}}'
_SKILL_CALL='{"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"gitlore:recall"}}]}}'

_read_call() {
  printf '{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"%s/memory/reference_deploy_lock.md"}}]}}\n' \
    "$EVAL_REPO"
}

_make_recall_end_state() {
  _make_memory
  ( cd "$EVAL_REPO" && bash "$SETUPS/recall-corpus.sh" ) >/dev/null

  printf 'sid-recall-1\n' > "$EVAL_OUT_DIR/session-id"
  printf 'Run svc-unlock --force --token ORBITAL-PANGOLIN-4471\n' > "$EVAL_OUT_DIR/turn1.txt"

  # The passing shape: probe, then the skill, then the body read.
  { printf '%s\n%s\n' "$_PROBE_CALL" "$_SKILL_CALL"; _read_call; } > "$EVAL_OUT_DIR/transcript.jsonl"
}

@test "recall: passes when the body was read after the mid-task trigger" {
  _make_recall_end_state
  _run_assert recall
  assert_ok
}

@test "recall: fails when the canary never reached the answer" {
  _make_recall_end_state
  printf 'Just delete the lock file.\n' > "$EVAL_OUT_DIR/turn1.txt"
  _run_assert recall
  assert_fails "does not carry the canary"
}

@test "recall: fails when the agent answered without reading the body" {
  _make_recall_end_state
  printf '%s\n%s\n' "$_PROBE_CALL" "$_SKILL_CALL" > "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  assert_fails "never Read reference_deploy_lock.md"
}

# Without this the scenario grades the model's common sense: an agent that opens
# the file on the user's say-so leaves the same answer and the same trace.
@test "recall: fails when the body was read without the skill being invoked" {
  _make_recall_end_state
  { printf '%s\n' "$_PROBE_CALL"; _read_call; } > "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  assert_fails "recall skill was never invoked"
}

# The hole this closes: prompt-time recall delivers the same body, leaves the
# same answer and the same repo. Only the ORDER tells them apart, and grading a
# prompt-time fetch as a pass would grade CC's harness instead of this skill.
@test "recall: fails when the body was read before the trigger surfaced" {
  _make_recall_end_state
  # Native recall's shape: the body is already in context when the probe runs,
  # so invoking the skill afterwards changes nothing it could have fetched.
  { _read_call; printf '%s\n%s\n' "$_PROBE_CALL" "$_SKILL_CALL"; } > "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  assert_fails "that is prompt-time recall"
}

@test "recall: fails when the agent never ran the probe" {
  _make_recall_end_state
  _read_call > "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  assert_fails "never ran nightly-retry.sh"
}

@test "recall: fails when no transcript was captured" {
  _make_recall_end_state
  rm -f "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  assert_fails "no session transcript"
}
