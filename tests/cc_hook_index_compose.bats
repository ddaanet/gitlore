#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

HOOK="$PLUGIN_ROOT/scripts/cc-hooks/index-compose.sh"
PRE="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
}
teardown() { teardown_tmp_repo; }

# The trigger is a two-step protocol, so the tests drive both halves: the
# PreToolUse hook stamps the watched files before the call, the batch's writes
# land, and the PostToolBatch hook composes if that stamp moved. Naming a file
# is no longer enough — the file has to change.
#
# $1 = the file an Edit announced, or the literal `Bash` for a call that
# announces nothing.
pre() {
  if [ "$1" = Bash ]; then
    printf '{"tool_name":"Bash","tool_input":{"command":"true"}}' | bash "$PRE"
  else
    jq -n --arg f "$1" '{tool_name:"Edit",tool_input:{file_path:$f}}' | bash "$PRE"
  fi
}

# The payload is drained and ignored; an empty object is a faithful stand-in.
feed() { printf '{}' | bash "$HOOK"; }

# A root index line AND the file it names, so the edit is a real fact rather
# than a dangling pointer the compose would report on.
seed_root_fact() {
  seed_root_bullet "$1" "$2"
  printf -- '---\nname: %s\ndescription: ""\n---\n\nbody\n' "$(basename "${1%.md}")" > "memory/$1"
}

@test "the hook is executable and registered on PostToolBatch" {
  [ -x "$HOOK" ]
  run jq -r '.hooks.PostToolBatch[].hooks[].command' "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *"index-compose.sh"* ]]
}

@test "no-op for a batch that touched neither the index nor the manifest" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/some/other/file.txt"
  # The pre hook's target filter is what this test is really about: an Edit to an
  # unrelated file leaves no baseline, so the batch is never even a candidate.
  # Without this line the silence below is the missing-baseline guard's, and
  # widening the filter to every file would go unnoticed.
  [ ! -f "$(gitlore_compose_stamp_file memory)" ]
  run feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run ! grep -qF 'ddaanet/shared.md' memory/MEMORY.md
}

@test "no-op for a batch that left no baseline behind" {
  seed_root_fact "p.md" "a project fact"   # changed, but no watched call ran
  run feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no-op when a watched call named the index but moved nothing" {
  # The tier bullet is unspliced and stays that way: a compose here would have
  # something to say, so the silence is the moved-nothing check and not an empty
  # store with nothing to report either way.
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md"
  # The positive half of the filter, over the same fixture as the test above:
  # naming the index DOES take a baseline. A rename of the stamp file turns this
  # red rather than quietly satisfying the other test's absence check.
  [ -f "$(gitlore_compose_stamp_file memory)" ]
  run feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run ! grep -qF 'ddaanet/shared.md' memory/MEMORY.md
}

@test "an index-touching batch composes and reports on both channels" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  run feed
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  [[ "$output" == *systemMessage* ]]
  [[ "$output" == *additionalContext* ]]
  run jq -e . <<<"$output"
  [ "$status" -eq 0 ]
}

@test "a Bash-applied index edit composes, though it named no file" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre Bash
  sed -i'' -e '$a\
- [P](p.md) — a project fact' memory/MEMORY.md
  printf -- '---\nname: p\ndescription: ""\n---\n\nbody\n' > memory/p.md
  run feed
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
}

@test "a manifest-touching batch recomposes" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  set_tier_manifest              # deactivate, so the batch's write is a change
  pre "$PWD/memory/.gitlore-tiers"
  set_tier_manifest ddaanet
  run feed
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
}

@test "an already-composed store reports nothing" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  feed >/dev/null
  # A second index edit, on a settled store: composition runs and finds nothing
  # left to splice or mirror, so it has nothing to say.
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "q.md" "another project fact"
  run feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a validation failure reports on both channels and exits 0" {
  pre "$PWD/memory/.gitlore-tiers"
  set_tier_manifest ghost
  run feed
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghost"* ]]
  [[ "$output" == *systemMessage* ]]
  [[ "$output" == *additionalContext* ]]
}

@test "a dangling pointer is reported even when nothing was composed" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  feed >/dev/null                      # settle the store
  pre "$PWD/memory/MEMORY.md"
  seed_root_bullet "gone.md" "stale line"
  run feed
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone.md"* ]]
  [[ "$output" == *systemMessage* ]]
  [[ "$output" == *additionalContext* ]]
  run jq -e . <<<"$output"
  [ "$status" -eq 0 ]
}

@test "a dangling report never rewrites or deletes anything" {
  pre "$PWD/memory/MEMORY.md"
  seed_root_bullet "gone.md" "stale line"
  feed >/dev/null
  # Composition may reflow the bullets, but the dangling line itself survives.
  grep -qF -- '- [gone](gone.md) — stale line' memory/MEMORY.md
  [ ! -e memory/gone.md ]
}

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

@test "no-op outside a gitlore repo" {
  local outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside"
  git -C "$outside" init -q
  cd "$outside"
  run feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
