#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

HOOK="$PLUGIN_ROOT/scripts/cc-hooks/index-compose.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
}
teardown() { teardown_tmp_repo; }

# Build a PostToolBatch payload naming the files an Edit/Write touched.
batch() {
  printf '{"tool_calls":['
  local first=1 f
  for f in "$@"; do
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$f"
  done
  printf ']}'
}

feed() { printf '%s' "$1" | bash "$HOOK"; }

@test "the hook is executable and registered on PostToolBatch" {
  [ -x "$HOOK" ]
  run jq -r '.hooks.PostToolBatch[].hooks[].command' "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *"index-compose.sh"* ]]
}

@test "no-op for a batch that touched neither the index nor the manifest" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  run feed "$(batch "$PWD/some/other/file.txt")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run ! grep -qF 'ddaanet/shared.md' memory/MEMORY.md
}

@test "no-op for a read-only batch" {
  run feed '{"tool_calls":[{"tool_name":"Read","tool_input":{"file_path":"x"}}]}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an index-touching batch composes and reports on both channels" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  run feed "$(batch "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  [[ "$output" == *systemMessage* ]]
  [[ "$output" == *additionalContext* ]]
  run jq -e . <<<"$output"
  [ "$status" -eq 0 ]
}

@test "a manifest-touching batch recomposes" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  run feed "$(batch "$PWD/memory/.gitlore-tiers")"
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
}

@test "an already-composed store reports nothing" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  feed "$(batch "$PWD/memory/MEMORY.md")" >/dev/null
  run feed "$(batch "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a validation failure reports on both channels and exits 0" {
  set_tier_manifest ghost
  run feed "$(batch "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghost"* ]]
  [[ "$output" == *systemMessage* ]]
  [[ "$output" == *additionalContext* ]]
}

@test "a dangling pointer is reported even when nothing was composed" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  feed "$(batch "$PWD/memory/MEMORY.md")" >/dev/null   # settle the store
  seed_root_bullet "gone.md" "stale line"
  run feed "$(batch "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone.md"* ]]
  [[ "$output" == *systemMessage* ]]
  [[ "$output" == *additionalContext* ]]
  run jq -e . <<<"$output"
  [ "$status" -eq 0 ]
}

@test "a dangling report never rewrites or deletes anything" {
  seed_root_bullet "gone.md" "stale line"
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  feed "$(batch "$PWD/memory/MEMORY.md")" >/dev/null
  # Composition may reflow the bullets, but the dangling line itself survives.
  grep -qF -- '- [gone](gone.md) — stale line' memory/MEMORY.md
  [ ! -e memory/gone.md ]
}

# --- Post-mount triage nudge (D17 triage-automation design) ---

@test "an index-only batch composes but emits no triage directive" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  run feed "$(batch "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  run -1 jq -e '.hookSpecificOutput.additionalContext | test("active-tier")' <<< "$output"
}

@test "a manifest-touching batch emits a triage directive naming the active tier's scope" {
  run feed "$(batch "$PWD/memory/.gitlore-tiers")"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("memory/ddaanet")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("org-wide facts for ddaanet")'
}

@test "the triage directive names every active tier's own scope, not a fixed dichotomy" {
  make_tier_in_memory otherteam
  set_tier_manifest ddaanet otherteam
  run feed "$(batch "$PWD/memory/.gitlore-tiers")"
  [ "$status" -eq 0 ]
  hookout="$output"
  jq -e '.hookSpecificOutput.additionalContext | test("org-wide facts for ddaanet")' <<< "$hookout"
  jq -e '.hookSpecificOutput.additionalContext | test("org-wide facts for otherteam")' <<< "$hookout"
  [[ "$hookout" != *"project-specific"* ]]
  [[ "$hookout" != *"single user"* ]]
}

@test "no triage directive when the manifest changes to zero active tiers" {
  run feed "$(batch "$PWD/memory/.gitlore-tiers")"
  [ "$status" -eq 0 ]
  set_tier_manifest
  run feed "$(batch "$PWD/memory/.gitlore-tiers")"
  [ "$status" -eq 0 ]
  # No active tier left to route to, so nothing is emitted at all — check the
  # raw string, not via jq, since a truly empty (no-JSON) output is the point.
  [[ "$output" != *"active-tier"* ]]
}

@test "no-op outside a gitlore repo" {
  local outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside"
  git -C "$outside" init -q
  cd "$outside"
  run feed "$(batch "$outside/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
