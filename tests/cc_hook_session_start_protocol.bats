#!/usr/bin/env bats
# The standing commit-protocol additionalContext session-start.sh emits every
# gitlore session: what it must say, and what it must not. Split from
# cc_hook_session_start.bats, which holds the hook's other behaviour.
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# Each @test is its own subshell, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2154,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/cc-hook-session-start

# Observed failure: asked to "add a note and commit it to memory", agents
# committed in the same turn, reading the request as the approval. The protocol
# carries one sentence that closes it; its two halves are pinned as literals
# (case-sensitive), so a rewording that flips the meaning cannot satisfy them.
@test "commit protocol says a request to commit is not approval of an unseen summary" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # Positive anchor: the protocol context is present at all.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ordinary edit"; "i")'
  echo "$output" | jq -e --arg s "A request to commit memory is not approval of a summary the user has not seen" '.hookSpecificOutput.additionalContext | contains($s)'
}

@test "commit protocol says to show the summary, end the turn, and commit after the reply approves" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # Positive anchor: the protocol context is present at all.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ordinary edit"; "i")'
  echo "$output" | jq -e --arg s "show the summary, end your turn, and commit only after the user's reply approves it" '.hookSpecificOutput.additionalContext | contains($s)'
}

# A skill step that acts on the store takes its path from this line, with no
# derivation call. The hook runs from the repo root, so $PWD/memory is the
# form it emits; the test and the hook share the same unresolved $PWD.
@test "protocol names the memory store's absolute path" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # Positive anchor: the protocol context is present at all.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ordinary edit"; "i")'
  echo "$output" | jq -e --arg s "the memory store is at $PWD/memory;" '.hookSpecificOutput.additionalContext | contains($s)'
  echo "$output" | jq -e --arg s "use this path" '.hookSpecificOutput.additionalContext | contains($s)'
  echo "$output" | jq -e --arg s "carries this line" '.hookSpecificOutput.additionalContext | contains($s)'
}

@test "emits standing commit-protocol additionalContext every gitlore session" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # The prohibition (the one piece that must precede any action) is present...
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("never run git commit inside the memory submodule"; "i")'
  # ...along with the happy path, as the acts it asks for: write the file like
  # any other edit, then commit memory through the gitlore:commit skill (D70),
  # which names the command; no config-key lookup rides the orientation.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ordinary edit"; "i")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("gitlore:commit")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("commitCommand|git config gitlore"; "i") | not'
  # A request to commit is not approval of a summary the user has not seen.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("not approval.*summary"; "i")'
  # A parent commit no longer carries memory, so the text must not say it does.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("committing the parent repo"; "i") | not'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("all it needs"; "i") | not'
  # ...but the persist *procedure* beyond that one command is NOT front-loaded —
  # no message-file path, no gate mechanism; the gate states them when it fires.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("explicit user approval"; "i") | not'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("rev-parse --git-path gitlore-commit-msg"; "i") | not'
  # No mechanism the agent cannot act on, and no FR id: the gate describes itself
  # when it fires, and an FR id resolves to nothing in a consumer repo.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("pre-commit"; "i") | not'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("approval gate"; "i") | not'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("FR[0-9]") | not'
  # Forbids by role, never by naming a command form to reason around.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("git -C"; "i") | not'
}
