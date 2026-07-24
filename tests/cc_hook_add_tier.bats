#!/usr/bin/env bats
# scripts/cc-hooks/add-tier-batch.sh — the PostToolBatch hook that runs the
# tier mount on the agent's behalf. D17 3-iii.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

BATCH="$PLUGIN_ROOT/scripts/cc-hooks/add-tier-batch.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=protocol.file.allow
  export GIT_CONFIG_VALUE_0=always
}
teardown() { teardown_tmp_repo; }

# The payload is unused (the intent file is the signal), so any JSON works.
run_batch() { printf '{"hook_event_name":"PostToolBatch","tool_calls":[]}' | bash "$BATCH"; }

write_intent() {
  mkdir -p .claude
  printf '%s\n' "$@" > .claude/gitlore-add-tier
}

# --- invocation path -------------------------------------------------------

@test "add-tier hook: wired on PostToolBatch and executable" {
  run jq -r '[.hooks.PostToolBatch[].hooks[].command | select(test("add-tier-batch"))] | length' \
    "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  [ -x "$PLUGIN_ROOT/scripts/cc-hooks/add-tier-batch.sh" ]
}

@test "add-tier hook: the command file is flat under commands/ (no double prefix)" {
  [ -f "$PLUGIN_ROOT/commands/add-tier.md" ]
  [ ! -e "$PLUGIN_ROOT/commands/gitlore" ]
}

# --- no-op paths -----------------------------------------------------------

@test "add-tier hook: no-op (exit 0, silent) when gitlore is not configured" {
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "add-tier hook: no-op when no intent file is present" {
  make_parent_with_memory
  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- the happy path --------------------------------------------------------

@test "add-tier hook: an intent file mounts the tier and consumes the intent" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run run_batch
  [ "$status" -eq 0 ]

  [ -e memory/ddaanet/.git ]
  [ ! -f .claude/gitlore-add-tier ]          # one-shot
}

@test "add-tier hook: reports on BOTH channels, activates, and recomposes" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run run_batch
  [ "$status" -eq 0 ]

  # systemMessage is the user-visible channel; additionalContext is model-only.
  sys=$(jq -r '.systemMessage' <<<"$output")
  ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "PostToolBatch" ]
  [[ "$sys" == *"mounted at memory/ddaanet"* ]]
  [[ "$ctx" == *".gitlore-tiers"* ]]
  [[ "$ctx" == *"Do not run any git yourself"* ]]

  # Activation is folded into the same hook call: no separate manifest edit,
  # and the recompose + triage nudge already fired.
  [ "$(cat memory/.gitlore-tiers)" = "ddaanet" ]
  [[ "$sys" == *"active-tier set changed"* ]]
}

@test "add-tier hook: splices the tier's own bullets into the root index too" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  push_tier_fact ddaanet >/dev/null
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run run_batch
  [ "$status" -eq 0 ]
  grep -q '(ddaanet/x.md)' memory/MEMORY.md
}

# --- failure ---------------------------------------------------------------

@test "add-tier hook: a failure still exits 0 so the JSON is not discarded" {
  make_parent_with_memory
  write_intent "mode=mount" "name=ddaanet" "url=$TMP_REPO/.no-such-remote.git"

  run run_batch
  # Exit 0 is load-bearing: stdout JSON parses on exit 0 only, so a non-zero
  # exit would DISCARD the report and make the failure less visible (D14).
  [ "$status" -eq 0 ]
  sys=$(jq -r '.systemMessage' <<<"$output")
  [[ "$sys" == *"submodule add failed"* ]]
  [ ! -e memory/ddaanet ]
}

@test "add-tier hook: a failed intent is consumed too, and says so" {
  make_parent_with_memory
  write_intent "mode=borrow" "name=ddaanet"

  run run_batch
  [ "$status" -eq 0 ]
  [ ! -f .claude/gitlore-add-tier ]
  ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")
  [[ "$ctx" == *"consumed"* ]]
  [[ "$ctx" == *"unknown mode"* ]]
}

# --- it does not clobber the sibling batch hooks ---------------------------

@test "add-tier hook: the intent file is gitignored, so the mount leaves no stray path" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"
  run run_batch
  [ "$status" -eq 0 ]

  # The intent lives in the PARENT's .claude/, which gitlore's own .gitignore
  # covers; assert the shipped ignore rule rather than the temp repo's.
  grep -qx '/.claude/gitlore-add-tier' "$PLUGIN_ROOT/.gitignore"
}
