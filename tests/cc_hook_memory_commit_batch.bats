#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

BATCH="$PLUGIN_ROOT/scripts/cc-hooks/memory-commit-batch.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

# The trigger file is the signal, so the payload carries nothing this hook acts
# on except `cwd` — read only to spot a trigger written against another root.
# Args: $1 = session cwd to report (default: none).
run_batch() {
  jq -nc --arg cwd "${1:-}" \
    '{hook_event_name:"PostToolBatch", tool_calls:[]} + (if $cwd == "" then {} else {cwd:$cwd} end)' \
    | bash "$BATCH"
}

# The model channel, which is what the agent actually reads.
ctx() { jq -r '.hookSpecificOutput.additionalContext // ""'; }

@test "no-op (exit 0, silent) when gitlore is not configured" {
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when no trigger file is present" {
  make_parent_with_memory
  echo dirty > memory/notes.md   # dirty, but nobody asked us to commit
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -n "$(git -C memory status --porcelain)" ]   # memory untouched
}

@test "trigger + approved summary commits memory, advances live, consumes both files" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory committed"* ]]
  # The agent asked for this commit and cannot see systemMessage (D14), so the
  # outcome it would otherwise go and check for itself rides the model channel,
  # carrying the new memory HEAD and standing the agent down from confirming it.
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"$(git -C memory log -1 --format='%h %s')"* ]]
  [[ "$agent" == *"do not run git status"* ]]

  # Memory committed and live advanced.
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record notes" ]
  # Both IPC files consumed.
  [ ! -f "$(gitlore_commit_trigger_file memory)" ]
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
}

@test "trigger without an approved summary keeps the trigger so it self-heals" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  : > "$(gitlore_commit_trigger_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"no approved summary"* ]]
  [[ "$output" == *"$(gitlore_commit_msg_file memory)"* ]]
  [[ "$output" == *blockquote* ]]   # present as a draft (> ...), not a code fence
  # The instruction is addressed to the agent, so it must reach the agent.
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"$(gitlore_commit_msg_file memory)"* ]]
  [[ "$agent" == *blockquote* ]]
  # Nothing committed, and the trigger is KEPT: the moment the summary is
  # written, the next batch commits transparently (no re-trigger needed).
  [ -n "$(git -C memory status --porcelain)" ]
  [ -f "$(gitlore_commit_trigger_file memory)" ]
}

@test "pending-summary message interpolates the canonical memory-approval clause" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  : > "$(gitlore_commit_trigger_file memory)"
  clause=$(cat "$PLUGIN_ROOT/reference/memory-approval-clause.txt")

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"$clause"* ]]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"$clause"* ]]
}

@test "a locked repo keeps both IPC files so the next batch retries transparently" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"

  # Simulate a held index lock — an expected transient. Don't actually sleep out
  # the retry backoff.
  export GITLORE_GIT_RETRY_SCHEDULE="0 0"
  : > "$(git -C memory rev-parse --git-dir)/index.lock"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"retry"* ]]
  # The retry is automatic; a blind agent either sits on it or re-triggers
  # pointlessly, so say both on the channel it reads.
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"deferred"* ]]
  [[ "$agent" == *"re-trigger"* ]]
  # Nothing committed, and BOTH files survive for the next attempt — no lost
  # approval, no agent action required.
  [ -n "$(git -C memory status --porcelain)" ]
  [ -f "$(gitlore_commit_trigger_file memory)" ]
  [ -f "$(gitlore_commit_msg_file memory)" ]
}

@test "trigger on clean memory reports nothing to commit and consumes the trigger" {
  make_parent_with_memory
  : > "$(gitlore_commit_trigger_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [[ "$output" == *"already clean"* ]]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"nothing to commit"* ]]
  [ ! -f "$(gitlore_commit_trigger_file memory)" ]
}

@test "a trigger written against another root is reported, not silently skipped" {
  # The handoff probe resolves the IPC dir from `git rev-parse --show-toplevel`
  # of the session cwd; this hook resolves it from CLAUDE_PROJECT_DIR. In a
  # linked worktree those disagree — CC chdirs into the worktree but leaves
  # CLAUDE_PROJECT_DIR at the launch repo — so the approved summary and trigger
  # land in the worktree's .claude/ while the hook reads the launch repo's, and
  # `[ -f "$trigger" ] || exit 0` made that a silent no-op: the user approved a
  # commit that never happened and nothing said so.
  make_parent_with_memory
  echo dirty > memory/notes.md
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  mkdir -p "$WT/.claude"
  printf 'memory: record notes\n' > "$WT/.claude/gitlore-memory-message"
  : > "$WT/.claude/gitlore-commit-memory"

  CLAUDE_PROJECT_DIR="$TMP_REPO" run run_batch "$WT"
  [ "$status" -eq 0 ]
  # Both roots named, on both channels: the user needs to know the approval did
  # not land, and the agent needs the two paths to move the files itself.
  [[ "$output" == *"$WT/.claude/gitlore-commit-memory"* ]]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"$WT/.claude/gitlore-commit-memory"* ]]
  [[ "$agent" == *"$(gitlore_commit_trigger_file memory)"* ]]
  [[ "$agent" == *"$(gitlore_commit_msg_file memory)"* ]]
  # Reported, not acted on: this hook commits the project root's memory, and a
  # trigger from another working tree is not authority to do that.
  [ -n "$(git -C memory status --porcelain)" ]
  [ -f "$WT/.claude/gitlore-commit-memory" ]
  rm -rf "$WT"
}

@test "no trigger anywhere stays silent — the stranded check must not fire on its own" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1

  CLAUDE_PROJECT_DIR="$TMP_REPO" run run_batch "$WT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$WT"
}

@test "no-op in a session-less worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  # A trigger is present, yet the guard must fire first: no memory worktree here.
  mkdir -p "$(dirname "$(gitlore_commit_trigger_file memory)")"
  : > "$(gitlore_commit_trigger_file memory)"
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$WT"
}
