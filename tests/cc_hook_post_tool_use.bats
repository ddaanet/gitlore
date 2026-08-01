#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

POST="$PLUGIN_ROOT/scripts/cc-hooks/post-tool-use.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  mkdir -p .claude
  jq -n --arg pc "lefthook run pre-commit" \
     '{gitlore: {enabled:true, precommitCommand:$pc}}' > .claude/settings.json
}
teardown() { teardown_tmp_repo; }

stdin() { printf '%s' "$1" | bash "$POST"; }

# The model channel, which is what the agent actually reads. The clause is
# multi-line, so it only survives as JSON — decode before matching on it.
ctx() { jq -r '.hookSpecificOutput.additionalContext // ""'; }

# Every no-op fixture below is the nudging fixture with exactly one thing
# flipped, so each stays falsifiable: dirty memory and a green pre-commit call
# are what make the hook speak, and a test that leaves memory clean would come
# out silent whichever guard was deleted.
payload() {   # $1 = tool_name, $2 = command, $3 = exit_code
  jq -nc --arg t "$1" --arg c "$2" --argjson e "$3" \
    '{tool_name:$t, tool_input:{command:$c}, tool_response:{exit_code:$e}}'
}
nudging_payload() { payload Bash "lefthook run pre-commit" 0; }

@test "no-op when tool_name is not Bash" {
  echo dirty > memory/notes.md
  run stdin "$(payload Read "lefthook run pre-commit" 0)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when command does not match precommit prefix" {
  echo dirty > memory/notes.md
  run stdin "$(payload Bash "echo unrelated" 0)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when the pre-commit run itself failed" {
  # A red pre-commit is not the moment to ask for a memory summary: the batch
  # the agent is about to fix would carry it.
  echo dirty > memory/notes.md
  run stdin "$(payload Bash "lefthook run pre-commit" 1)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when memory is clean" {
  run stdin "$(nudging_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "emits additionalContext when memory is dirty and matched" {
  echo dirty > memory/notes.md
  run stdin "$(nudging_payload)"
  [ "$status" -eq 0 ]
  [[ "$output" == *additionalContext* ]]
  [[ "$output" == *"Summarize pending memory changes"* ]]
  [[ "$output" == *blockquote* ]]   # present as a draft (> ...), not a code fence
}

@test "additionalContext interpolates the canonical memory-approval clause" {
  echo dirty > memory/notes.md
  clause=$(cat "$PLUGIN_ROOT/reference/memory-approval-clause.txt")
  run stdin "$(nudging_payload)"
  # The clause spans lines, so the emission must be real JSON — a hand-written
  # string would carry a raw newline and parse as nothing at all.
  echo "$output" | jq -e . >/dev/null
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"$clause"* ]]
}

@test "no-op when .claude/settings.json is missing" {
  echo dirty > memory/notes.md
  rm -f .claude/settings.json
  run stdin "$(nudging_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when settings.json configures no precommit command" {
  echo dirty > memory/notes.md
  jq -n '{gitlore: {enabled:true}}' > .claude/settings.json
  run stdin "$(nudging_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when commit-msg file is fresh" {
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'pre-approved\n' > "$msgfile"
  touch "$msgfile"
  run stdin "$(nudging_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "nudges only once per dirty episode" {
  echo dirty > memory/notes.md
  run stdin "$(nudging_payload)"
  [[ "$output" == *additionalContext* ]]   # first green pre-commit nudges
  run stdin "$(nudging_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                          # second, same episode, stays silent
}

@test "committing memory ends the episode and re-enables the nudge" {
  echo dirty > memory/notes.md
  run stdin "$(nudging_payload)"
  [[ "$output" == *additionalContext* ]]

  # Commit memory (clears the once-per-episode marker), then dirty it anew.
  bash "$PLUGIN_ROOT/scripts/commit-memory.sh" -m "memory: notes"
  echo more > memory/more.md
  run stdin "$(nudging_payload)"
  [[ "$output" == *additionalContext* ]]   # a fresh episode nudges again
}
