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

# The payload is otherwise unused (the intent file is the signal). $1 = agent
# id, optional — absent/empty omits `agent_id` entirely (a main-thread
# batch); non-empty adds it, the same absent-vs-non-empty contract
# scripts/lib/index-sync.sh's own helpers use. Every call also carries
# `agent_type`, the shape a real `--agent`-session payload has whether or not
# it carries `agent_id` too — the decoy a hook that falls back to
# `agent_type` would key on by mistake.
run_batch() {
  local agent="${1:-}"
  jq -n --arg a "$agent" \
    '{hook_event_name:"PostToolBatch", tool_calls:[], agent_type:"general-purpose"}
     + (if $a == "" then {} else {agent_id:$a} end)' | bash "$BATCH"
}

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

# --- no-op paths -----------------------------------------------------------

@test "add-tier hook: no-op (exit 0, silent) when gitlore is not configured" {
  # The mount fixture minus exactly the submodule: a well-formed intent is
  # waiting, so but for the not-configured guard this batch would mount and
  # speak. Without the intent the run would reach the no-intent guard and come
  # out silent whether the configured check is there or not.
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  run run_batch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f .claude/gitlore-add-tier ]           # and the intent is left for later
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

# The compose-baseline drop this hook does after a successful mount
# (add-tier-batch.sh, the `rm -f "$(gitlore_compose_stamp_file …)"` right
# after activation) must target the SAME keyed name index-compose.sh itself
# would consume for this agent — otherwise a subagent's own compose baseline
# would be left behind (a leak, though a bounded one) while an unrelated
# main-thread baseline it never owned gets dropped instead. Today the hook
# reads no agent id at all and always targets the bare name, so this reds on
# the bare stamp vanishing and the keyed one surviving — backwards from what
# is asserted.
@test "add-tier hook: drops the compose baseline for its own agent, leaves the bare one" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  keyed=$(gitlore_compose_stamp_file memory a1)
  bare_stamp=$(gitlore_compose_stamp_file memory)
  printf 'index\tstale\n' > "$keyed"
  printf 'index\tstale\n' > "$bare_stamp"

  run run_batch a1
  [ "$status" -eq 0 ]

  [ ! -f "$keyed" ]
  [ -f "$bare_stamp" ]
}

# The mirror, and the only case in this file that pins WHICH field keys the
# drop. The case above cannot: its payload carries `agent_id`, so a hook
# reading `.agent_id // .agent_type` resolves the same "a1" and passes. Here
# the payload has the decoy and nothing else — the shape a main-thread batch
# inside an `--agent` session really has — so a fallback drops a name no
# pre-hook ever wrote and strands the parent's own baseline. Passes against
# today's unkeyed code, which is the point: it is the guard that the empty id
# keeps resolving today's bare name.
@test "add-tier hook: a main-thread batch drops the bare compose baseline, not an agent_type-keyed one" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"

  bare_stamp=$(gitlore_compose_stamp_file memory)
  decoy=$(gitlore_compose_stamp_file memory general-purpose)
  printf 'index\tstale\n' > "$bare_stamp"
  printf 'index\tstale\n' > "$decoy"

  run run_batch
  [ "$status" -eq 0 ]

  [ ! -f "$bare_stamp" ]
  [ -f "$decoy" ]
}

# The intent, not the payload, asks for the mount, so an unparseable payload
# must not abort one. Reds when the hook's `|| agent_id=""` fallback is
# removed: jq's parse failure then kills the hook under errexit, exiting
# non-zero before add-tier.sh runs, so nothing mounts.
@test "add-tier hook: an unparseable payload still mounts and drops the bare compose baseline" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"
  bare_stamp=$(gitlore_compose_stamp_file memory)
  printf 'index\tstale\n' > "$bare_stamp"

  # shellcheck disable=SC2016  # $1 expands inside the bash -c script, not here
  run --separate-stderr bash -c 'printf "not json" | bash "$1"' _ "$BATCH"
  [ "$status" -eq 0 ]
  [ -e memory/ddaanet/.git ]
  [ ! -f .claude/gitlore-add-tier ]
  [ ! -f "$bare_stamp" ]
  sys=$(jq -r '.systemMessage' <<<"$output")
  [[ "$sys" == *"mounted at memory/ddaanet"* ]]
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
