#!/usr/bin/env bash
# Sourced by the assertions that grade a memory commit. The caller defines
# `fail <reason>` (print, exit 1) and has EVAL_REPO / PLUGIN_ROOT in the
# environment.
#
# After the user approves, the agent commits memory by invoking the
# `gitlore:commit` skill and piping the approved sectioned summary to
# `gitlore-commit`. The assertions grade the outcome (memory moved past the
# baseline) and the trace (the skill came before the commit).

# settle_commit_path <memory-dir> <baseline-sha>
# Passes when memory committed, or fails. Sets `path_taken` for the failure
# messages of the checks that follow.
settle_commit_path() {
  local mem="$1" baseline="$2"
  if [ "$(git -C "$mem" rev-parse HEAD)" != "$baseline" ]; then
    path_taken="the agent committed memory itself"
    return 0
  fi
  fail "memory never moved — the agent did not commit the approved summary after Turn 2"
}

# check_commit_trace
# The session transcript must show the `gitlore:commit` Skill call ahead of a
# Bash command running `gitlore-commit`. The eval fixture copies the skills in as
# project skills, so the same skill is named `commit` there; both names count. A raw `git commit` moves memory too, so
# only the transcript tells the skill's path from a bypass.
check_commit_trace() {
  local transcript="$EVAL_OUT_DIR/transcript.jsonl" trace skill_at after_at any_at
  [ -s "$transcript" ] || fail "no session transcript at $transcript; the harness did not capture the run"
  # Indices of the first gitlore:commit Skill call, the first gitlore-commit Bash
  # command after it, and the first one anywhere (-1 when absent). A mention
  # ahead of the skill, such as a `command -v` probe, does not fail a run whose
  # real commit follows the skill.
  trace=$(jq -rs '
    [.[] | .message.content[]? | select(.type == "tool_use")]
    | to_entries as $t
    | ($t | map(select(.value.name == "Skill" and (.value.input.skill == "gitlore:commit" or .value.input.skill == "commit"))) | first | .key // -1) as $skill
    | ($t | map(select(.value.name == "Bash" and ((.value.input.command // "") | contains("gitlore-commit")))) | map(.key)) as $bash
    | [$skill, ($bash | map(select(. > $skill)) | first // -1), ($bash | first // -1)]
    | map(tostring) | join(" ")' "$transcript") || \
    fail "could not read the session transcript $transcript"
  read -r skill_at after_at any_at <<<"$trace"
  [ "$skill_at" != "-1" ] || fail "the gitlore:commit skill was never invoked"
  [ "$any_at" != "-1" ] || fail "gitlore-commit was never run"
  [ "$after_at" != "-1" ] || fail "gitlore-commit ran before the gitlore:commit skill was invoked"
}

# check_no_commit_before_approval <baseline-sha>
# The runner snapshots memory's HEAD at the end of turn 1, before the approval
# message. A HEAD that moved by then was committed before the user approved. An
# empty snapshot is read as absent.
check_no_commit_before_approval() {
  local baseline="$1" after1=""
  if [ -s "$EVAL_OUT_DIR/memory-after-turn1" ]; then
    after1=$(cat "$EVAL_OUT_DIR/memory-after-turn1")
  fi
  if [ -n "$after1" ] && [ "$after1" != "$baseline" ]; then
    fail "memory was committed before approval — HEAD moved during turn 1, ahead of the approval message"
  fi
}

# check_memory_pointer_staged
# The commit moved memory HEAD, so the parent must record the memory gitlink at
# that sha — otherwise the user's next parent commit records a stale pointer.
# Passes when the index entry or the parent's HEAD is memory's current HEAD. A
# clean index still lists the path, at HEAD's sha, so one comparison covers both
# "staged" and "already committed".
check_memory_pointer_staged() {
  local want idx_line idx_sha head_sha
  want=$(git -C "$EVAL_REPO/memory" rev-parse HEAD) || \
    fail "could not read memory's HEAD"
  [ -n "$want" ] || fail "could not read memory's HEAD"
  idx_line=$(git -C "$EVAL_REPO" ls-files -s -- memory)
  read -r _ idx_sha _ <<<"$idx_line"
  head_sha=$(git -C "$EVAL_REPO" rev-parse -q --verify HEAD:memory)
  if [ "$idx_sha" != "$want" ] && [ "$head_sha" != "$want" ]; then
    fail "the parent index does not have 'memory' staged after the commit ($path_taken) — the gitlink floats until the user stages it"
  fi
}
