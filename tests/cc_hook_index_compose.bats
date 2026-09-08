#!/usr/bin/env bats
# feed()'s agent id is optional and most calls below omit it (a main-thread
# call), which is what SC2119/SC2120 flag as suspicious at the three bare
# `feed >/dev/null` sites — the argument is genuinely optional. Scoped to this
# file rather than to the function because SC2119 fires at the call sites.
# shellcheck disable=SC2119,SC2120
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
# announces nothing. $2 = agent id, optional — absent/empty omits `agent_id`
# entirely (a main-thread call); non-empty adds it, the same
# absent-vs-non-empty contract scripts/lib/index-sync.sh's own helpers use.
# Every call also carries `agent_type`, the shape a real `--agent`-session
# payload has whether or not it carries `agent_id` too — the decoy a hook
# that falls back to `agent_type` would key on by mistake.
pre() {
  local agent="${2:-}"
  if [ "$1" = Bash ]; then
    jq -n --arg a "$agent" \
      '{tool_name:"Bash",tool_input:{command:"true"},agent_type:"general-purpose"}
       + (if $a == "" then {} else {agent_id:$a} end)' | bash "$PRE"
  else
    jq -n --arg f "$1" --arg a "$agent" \
      '{tool_name:"Edit",tool_input:{file_path:$f},agent_type:"general-purpose"}
       + (if $a == "" then {} else {agent_id:$a} end)' | bash "$PRE"
  fi
}

# $1 = agent id, optional — same absent-vs-non-empty contract as pre()'s
# second argument, and the same agent_type decoy. The payload's CONTENTS are
# still drained rather than acted on for composition itself; only the agent
# id is meant to steer which baseline this run consumes.
feed() {
  local agent="${1:-}"
  jq -n --arg a "$agent" \
    '{agent_type:"general-purpose"} + (if $a == "" then {} else {agent_id:$a} end)' \
    | bash "$HOOK"
}

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
  run -1 grep -qF 'ddaanet/shared.md' memory/MEMORY.md
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
  run -1 grep -qF 'ddaanet/shared.md' memory/MEMORY.md
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
  printf '%s\n' '- [P](p.md) — a project fact' >> memory/MEMORY.md
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

# The race Item 2.1 exists to close, for the compose hook: a parent batch's
# own compose baseline must survive a subagent's compose run, which is keyed
# differently. `pre()` with no agent id establishes the bare stamp (a
# main-thread call, decoyed with `agent_type` per the file header); `feed a1`
# then drives index-compose.sh as if from within a subagent's own
# PostToolBatch. Today the hook reads no agent id at all — it always resolves
# the bare stamp — so this reds on the hook composing (and reporting, and
# consuming the bare stamp) when it should stay silent and leave that
# baseline alone.
@test "a main-thread compose baseline survives a subagent's compose hook" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md"
  [ -f "$(gitlore_compose_stamp_file memory)" ]
  seed_root_fact "p.md" "a project fact"
  run feed a1
  [ "$status" -eq 0 ]
  # Survival first, silence second: a bats body runs under errexit, so only the
  # first of the two is exercised at RED, and the stranded parent edit this
  # assertion catches is the silent bug the item exists to close — the stray
  # report the next one catches is merely noise. Each is independently
  # load-bearing all the same: a GREEN that exits silently but still drops the
  # bare stamp is caught only here, and one that reports with no baseline of
  # its own only below.
  [ -f "$(gitlore_compose_stamp_file memory)" ]
  [ -z "$output" ]
}

# The positive half of the pair above, and the only case in this file where a
# subagent's compose hook has a baseline of its own to act on. Without it, a
# hook that simply gives up whenever `agent_id` is set — or one that keys the
# stamp LOOKUP and leaves the removal on the bare name — satisfies every other
# case in both suites. A parent batch is in flight at the same time (the second
# `pre`, with no agent id), so which name the subagent resolved is observable
# from both sides: its own stamp must be gone and the parent's must not.
@test "a subagent's compose consumes its own baseline, not the main thread's" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md" a1
  pre "$PWD/memory/MEMORY.md"
  keyed=$(gitlore_compose_stamp_file memory a1)
  bare=$(gitlore_compose_stamp_file memory)
  # Both guards run before the SUT, so the `! -f` below cannot pass vacuously
  # on a stamp that was never written in the first place.
  [ -f "$keyed" ]
  [ -f "$bare" ]
  seed_root_fact "p.md" "a project fact"
  run feed a1
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  [[ "$output" == *systemMessage* ]]
  [ ! -f "$keyed" ]
  [ -f "$bare" ]
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

@test "no-op outside a gitlore repo" {
  local outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside"
  git -C "$outside" init -q
  cd "$outside"
  run feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
