#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

BATCH="$PLUGIN_ROOT/scripts/cc-hooks/recall-batch.sh"
RESET="$PLUGIN_ROOT/scripts/cc-hooks/recall-reset.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

# The request file is the signal; tool_calls only feed the ledger.
run_batch() {
  local calls="${1:-[]}"
  printf '{"hook_event_name":"PostToolBatch","session_id":"sess-1","tool_calls":%s}' "$calls" \
    | bash "$BATCH"
}
run_reset() {
  printf '{"hook_event_name":"PreCompact","session_id":"sess-1"}' | bash "$RESET"
}
read_call() { printf '[{"tool_name":"Read","tool_input":{"file_path":"%s"}}]' "$1"; }

@test "hooks are executable and discovered as such" {
  [ -x "$BATCH" ]
  [ -x "$RESET" ]
}

@test "both hooks are registered in hooks.json" {
  run jq -r '[.hooks | .. | .command? // empty] | join("\n")' "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cc-hooks/recall-batch.sh"* ]]
  [[ "$output" == *"cc-hooks/recall-reset.sh"* ]]
  run jq -r '.hooks | keys | join(" ")' "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *"PreCompact"* ]]
}

@test "no-op (exit 0, silent) when gitlore is not configured" {
  # A repo that has a memory/ directory and even a pending request in it, but no
  # .gitmodules entry — so gitlore does not manage this store and must not read
  # from it. Named after the submodule path on purpose: the guard is what tells
  # the two apart, and a fixture without the directory would be silent whether
  # the guard held or not.
  git init -q -b main memory
  printf 'body of A\n' > memory/feedback_a.md
  mkdir -p .claude
  printf 'feedback_a.md\n' > "$(gitlore_recall_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run run_reset
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$(gitlore_recall_file memory)" ]   # and the request is left untouched
}

@test "no-op in a session-less worktree where the memory worktree is absent" {
  # git creates the gitlink directory but leaves the submodule uninitialised, so
  # there is no store to read. The request is present, so the silence is this
  # guard's and not the missing-request one's.
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  mkdir -p .claude
  printf 'feedback_a.md\n' > "$(gitlore_recall_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$WT"
}

@test "no-op when no request file is present" {
  make_parent_with_memory
  printf 'body of A\n' > memory/feedback_a.md
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a request injects the bodies as additionalContext and is consumed" {
  make_parent_with_memory
  printf 'body of A\n' > memory/feedback_a.md
  printf 'feedback_a.md\n' > "$(gitlore_recall_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"body of A"* ]]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = "PostToolBatch" ]
  [[ "$(printf '%s' "$output" | jq -r '.systemMessage')" == *"recalled 1 memory"* ]]

  [ ! -f "$(gitlore_recall_file memory)" ]     # consumed
}

@test "no match reports and fetches nothing" {
  make_parent_with_memory
  printf 'no match\n' > "$(gitlore_recall_file memory)"
  run run_batch
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.systemMessage')" == *"no match"* ]]
  [ ! -f "$(gitlore_recall_file memory)" ]
}

@test "a rejected request is consumed too, so it cannot re-report forever" {
  make_parent_with_memory
  printf 'feedback_nope.md\n' > "$(gitlore_recall_file memory)"

  run run_batch
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"REFUSED"* ]]
  [[ "$ctx" == *"feedback_nope.md"* ]]
  # The banner states it once; the resolver's report must not repeat it.
  [ "$(printf '%s\n' "${ctx,,}" | grep -c "${GITLORE_T_NOTHING_READ,,}")" -eq 1 ]
  [ ! -f "$(gitlore_recall_file memory)" ]

  run run_batch          # nothing left to report
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a Read in the batch is ledgered, so the same body is not re-sent" {
  make_parent_with_memory
  printf 'body of A\n' > memory/feedback_a.md
  abs="$TMP_REPO/memory/feedback_a.md"

  # A prior batch read it directly — this is also the shape of CC's own
  # "Recalled 1 memory", which issues a real Read on the agent's behalf.
  run run_batch "$(read_call "$abs")"
  [ "$status" -eq 0 ]

  printf 'feedback_a.md\n' > "$(gitlore_recall_file memory)"
  run run_batch
  [ "$status" -eq 0 ]
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"already in this context"* ]]
  [[ "$ctx" != *"body of A"* ]]
}

@test "a Read outside the memory store is not ledgered" {
  make_parent_with_memory
  printf 'body of A\n' > memory/feedback_a.md
  printf 'decoy\n' > "$TMP_REPO/feedback_a.md"

  run run_batch "$(read_call "$TMP_REPO/feedback_a.md")"
  [ "$status" -eq 0 ]

  printf 'feedback_a.md\n' > "$(gitlore_recall_file memory)"
  run run_batch
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"body of A"* ]]
}

@test "reset clears the ledger so a post-compaction request re-fetches" {
  make_parent_with_memory
  printf 'body of A\n' > memory/feedback_a.md
  printf 'feedback_a.md\n' > "$(gitlore_recall_file memory)"
  run run_batch
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == *"body of A"* ]]

  run run_reset
  [ "$status" -eq 0 ]

  printf 'feedback_a.md\n' > "$(gitlore_recall_file memory)"
  run run_batch
  ctx=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *"body of A"* ]]      # re-fetched, not skipped
}

@test "reset also clears the budget-nudge marker" {
  make_parent_with_memory
  marker=$(gitlore_index_budget_nudge_file memory sess-1)
  mkdir -p "$(dirname "$marker")"
  touch "$marker"
  run run_reset
  [ "$status" -eq 0 ]
  [ ! -f "$marker" ]
}

@test "batch and reset agree on one ledger when the session cwd has drifted" {
  # CC's in-process EnterWorktree moves the session cwd but freezes
  # CLAUDE_PROJECT_DIR (D15). Every hook anchors on the launch repo, because
  # that is where auto-memory keeps writing. A hook that followed cwd instead
  # would ledger in one store while reset cleared another, and the ledger would
  # never be cleared across a compaction.
  make_parent_with_memory
  printf 'body of A\n' > memory/feedback_a.md
  export CLAUDE_PROJECT_DIR="$TMP_REPO"
  ledger_req="$(gitlore_recall_file "$TMP_REPO/memory")"
  mkdir -p elsewhere
  cd elsewhere || return 1

  printf 'feedback_a.md\n' > "$ledger_req"
  run run_batch
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == *"body of A"* ]]

  printf 'feedback_a.md\n' > "$ledger_req"
  run run_batch
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == *"already in this context"* ]]

  run run_reset
  [ "$status" -eq 0 ]
  printf 'feedback_a.md\n' > "$ledger_req"
  run run_batch
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" == *"body of A"* ]]
}

@test "every cc-hook anchors on the launch repo before it touches a repo" {
  # One convention or none: a mix is what let the recall ledger be written in
  # one store and cleared in another.
  for hook in "$PLUGIN_ROOT"/scripts/cc-hooks/*.sh; do
    case "${hook##*/}" in
      # Comparing the session cwd with the launch root IS this hook's job.
      worktree-drift.sh) continue ;;
    esac
    grep -qF 'gitlore_cd_project_root' "$hook" || {
      echo "no gitlore_cd_project_root in $hook" >&2
      return 1
    }
  done
}
