#!/usr/bin/env bats
# feed()'s agent id is optional and most calls below omit it (a main-thread
# call), which is what SC2119/SC2120 flag as suspicious at the bare
# `feed >/dev/null` sites — the argument is genuinely optional. Scoped to this
# file rather than to the function because SC2119 fires at the call sites.
# shellcheck disable=SC2119,SC2120
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/cc-hook-index-compose

# --- Post-mount triage nudge (D17 triage-automation design) ---

@test "an index-only batch composes but emits no triage directive" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  run feed
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  # shellcheck disable=SC2016 # $m is a jq variable, bound by --arg
  run -1 jq -e --arg m "$GITLORE_T_TRIAGE_MARK" \
    '.hookSpecificOutput.additionalContext | test($m)' <<< "$output"
}

@test "a manifest-touching batch emits a triage directive naming the active tier's scope" {
  set_tier_manifest
  pre "$PWD/memory/.gitlore-tiers"
  set_tier_manifest ddaanet
  run feed
  [ "$status" -eq 0 ]
  # The marker the two "no directive" negatives refute, pinned positively over
  # the same fixture they use — differing only in whether the batch touched the
  # manifest. Without this, a rewording of the nudge leaves both of them green
  # and watching nothing.
  # shellcheck disable=SC2016 # $m is a jq variable, bound by --arg
  echo "$output" | jq -e --arg m "$GITLORE_T_TRIAGE_MARK" \
    '.hookSpecificOutput.additionalContext | test($m)'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("memory/ddaanet")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("org-wide facts for ddaanet")'
  # The judgement the nudge asks for is the skill's tier test, so the nudge
  # names the skill rather than restating it.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("gitlore:memory-writing")'
}

@test "no triage directive when the manifest changes to zero active tiers" {
  pre "$PWD/memory/.gitlore-tiers"
  set_tier_manifest
  run feed
  [ "$status" -eq 0 ]
  # No active tier left to route to, so nothing is emitted at all — check the
  # raw string, not via jq, since a truly empty (no-JSON) output is the point.
  [[ "$output" != *"$GITLORE_T_TRIAGE_MARK"* ]]
}

# --- a store with no root index ---

@test "a store with no root index says composition and the index checks are off" {
  # SessionStart writes the scaffold back, so reaching here means the file went
  # away inside the session. Until it returns, nothing places a tier's pointer
  # lines, no validation guards what is written, and Claude Code loads no index
  # at all — and every one of those failures is silent.
  rm memory/MEMORY.md
  run feed
  [ "$status" -eq 0 ]
  json="$output"
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no root MEMORY.md"* ]]
  [[ "$output" == *"# Memory Index"* ]]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [ "$status" -eq 0 ]
  # The file to write, named from the project root the hooks and the agent
  # share — the same spelling every sibling notice uses.
  [[ "$output" == *"memory/MEMORY.md"* ]]
  [[ "$output" == *"# Memory Index"* ]]
  # Reported, never repaired here: writing the store is the approval gate's,
  # and a file this hook created would arrive with no commit accounting for it.
  [ ! -e memory/MEMORY.md ]
}

@test "the no-root-index notice fires once per session" {
  # It answers a store-level condition, not a batch: unguarded it would repeat
  # on every batch of the session, and each repeat costs the user's channel and
  # the agent's context.
  rm memory/MEMORY.md
  run feed
  [ "$status" -eq 0 ]
  [[ "$output" == *"no root MEMORY.md"* ]]

  run feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a compaction re-arms the no-root-index notice" {
  # What survives a compaction is a summary, so a notice this session was
  # already given may no longer be in the context it was given to.
  rm memory/MEMORY.md
  feed >/dev/null
  run feed
  [ -z "$output" ]

  printf '{"hook_event_name":"PreCompact","session_id":"test-session"}' \
    | bash "$PLUGIN_ROOT/scripts/cc-hooks/nudge-reset.sh"

  run feed
  [ "$status" -eq 0 ]
  [[ "$output" == *"no root MEMORY.md"* ]]
}

@test "a subagent's no-root-index notice is staged for the parent" {
  # A hook's output inside a subagent reaches that subagent alone (D51), and
  # the marker is keyed by session: without the relay the one notice the
  # session gets would be spent where nobody else reads it.
  rm memory/MEMORY.md
  run feed a1
  [ "$status" -eq 0 ]
  [[ "$output" == *"no root MEMORY.md"* ]]
  marker=$(relay_marker_for memory a1)
  [ -f "$marker" ]
  grep -qF 'no root MEMORY.md' "$marker"
}

@test "no-op outside a gitlore repo" {
  local outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside"
  git -C "$outside" init -q
  cd "$outside"
  run feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
