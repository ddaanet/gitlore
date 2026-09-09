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
POST="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"

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

# Drives index-sync-post.sh the same way feed() drives index-compose.sh: $1 =
# agent id, optional, same absent-vs-non-empty contract. The hook never
# inspects tool_calls/session_id (its own pre-hook's stash is what drives it —
# scripts/cc-hooks/index-sync-post.sh's own header comment), so a minimal
# PostToolBatch envelope is enough. Item 3.1 slice 2.5's own case is the only
# one in this file that needs the sync hook, alongside the compose hook,
# inside the same batch.
sync_feed() {
  local agent="${1:-}"
  jq -n --arg a "$agent" --arg s test-session \
    '{hook_event_name:"PostToolBatch", session_id:$s, tool_calls:[], tool_results:[],
      agent_type:"general-purpose"} + (if $a == "" then {} else {agent_id:$a} end)' \
    | bash "$POST"
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

# Item 3.1/D: a hook firing inside a subagent has its report confined to that
# subagent's own transcript, so the compose hook relays it through a marker
# for the next parent-side (unkeyed) run to fold in. The subagent still gets
# its own copy on its own channel — "in addition to, not instead of" — so the
# JSON/systemMessage assertions below are already true today; only the marker
# half is new.
@test "a keyed compose run writes a marker and still emits its own json" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md" a1
  seed_root_fact "p.md" "a project fact"
  run feed a1
  [ "$status" -eq 0 ]
  json="$output"
  # Through jq rather than a substring match on the raw JSON: the field is
  # what "its own copy" means, and jq -r fails on malformed output, so the
  # two halves of "valid JSON carrying the compose report" are one assertion.
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recomposed tier pointers"* ]]
  marker=$(gitlore_relay_marker_file memory a1)
  [ -f "$marker" ]
  grep -qF 'recomposed tier pointers' "$marker"
}

# The positive half: with a keyed marker already staged, the next unkeyed
# (parent-side) compose run folds it into its own report — on the same
# channel, attributed to the agent that left it — and removes it. Planted
# directly via gitlore_relay_write (Item 3.1 slice 1, already committed)
# rather than via a real keyed hook run, so this case is isolated from
# whether the hook itself writes the marker (the case above).
@test "an unkeyed compose run folds in the marker and removes it" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_relay_write memory a1 "keyed relay sysmsg a1" "keyed relay ctx a1"
  marker=$(gitlore_relay_marker_file memory a1)
  [ -f "$marker" ]
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  run feed
  [ "$status" -eq 0 ]
  json="$output"
  # Per channel, not over the raw JSON blob: the framing line and the body
  # both reach additionalContext too, so a substring match on the whole
  # object passes for a fold that reached only the model's channel and never
  # the user's.
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recomposed tier pointers"* ]]
  [[ "$output" == *"gitlore-relay agent a1"* ]]
  [[ "$output" == *"keyed relay sysmsg a1"* ]]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore-relay agent a1"* ]]
  [[ "$output" == *"keyed relay ctx a1"* ]]
  [ ! -f "$marker" ]
}

# The constraint neither case above can see, and the one the slice exists to
# protect: a parent-side run whose ONLY report is a relayed one must still
# emit. Both hooks guard emission on their own report being non-empty
# (index-compose.sh:68, index-sync-post.sh:243), so a fold placed AFTER that
# guard is correct in every case where the hook has something of its own to
# say — which is every other case in this slice — and silently drops the
# relay here.
#
# The fixture is "an already-composed store reports nothing" above with a
# marker added: the first compose settles the store, then a second index edit
# takes a baseline and moves the index, so the hook runs all the way to the
# emission point and composition finds nothing left to do. The negative
# assertion on its own report is what makes the case discriminate — without
# it a hook that still had something to say would satisfy it too.
@test "an unkeyed compose run with no report of its own still emits the relay" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  feed >/dev/null
  gitlore_relay_write memory a1 "keyed relay sysmsg a1" "keyed relay ctx a1"
  marker=$(gitlore_relay_marker_file memory a1)
  [ -f "$marker" ]
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "q.md" "another project fact"
  run feed
  [ "$status" -eq 0 ]
  json="$output"
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" != *"recomposed tier pointers"* ]]
  [[ "$output" == *"gitlore-relay agent a1"* ]]
  [[ "$output" == *"keyed relay sysmsg a1"* ]]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"keyed relay ctx a1"* ]]
  [ ! -f "$marker" ]
}

# The seam the two cases above leave open. The first asserts a marker exists
# and holds the report text; the second folds a marker this file wrote for
# itself with gitlore_relay_write. Nothing makes the two halves agree on the
# on-disk FORMAT: a hook writing the raw body with no
# `--- gitlore-relay-sysmsg ---` delimiter satisfies both, and
# gitlore_relay_drain's awk then yields an empty body — the parent gets a
# framing line wrapped around nothing. So: a marker written by a real keyed
# run, folded by a real unkeyed one.
#
# The keyed run leaves the store composed, so the unkeyed run has nothing of
# its own to say and every line it emits came out of the marker. That is what
# lets `recomposed tier pointers` in the parent's report pin the seam without
# depending on where in the report the relayed block lands.
@test "an unkeyed compose run folds in a marker a keyed run wrote" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md" a1
  seed_root_fact "p.md" "a project fact"
  feed a1 >/dev/null
  marker=$(gitlore_relay_marker_file memory a1)
  [ -f "$marker" ]
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "q.md" "another project fact"
  run feed
  [ "$status" -eq 0 ]
  json="$output"
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore-relay agent a1"* ]]
  [[ "$output" == *"recomposed tier pointers"* ]]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier composition rewrote these indexes"* ]]
  [ ! -f "$marker" ]
}

# Item 3.1 slice 2.5. hooks.json registers index-sync-post.sh and
# index-compose.sh on the SAME PostToolBatch event, in that order, and both now
# stage to gitlore_relay_marker_file's one path per agent. Adapted from the
# code review's hand-run transcript (item-3-1-s2-code-review.md §F1): same
# fixture shape — pre + a root index edit that gives BOTH hooks a real report,
# then a real keyed run of each in hooks.json's own order, then an unkeyed
# parent-side run. Differs from that transcript in driving index-sync-post.sh
# through a real script invocation (sync_feed) rather than a manual `bash`
# call, and in asserting on the drained PARENT report rather than on the
# marker's raw bytes — the case the helper-level "relay_write merges a second
# report" test (tests/index_sync.bats) cannot see, since it never drives a
# hook.
@test "both PostToolBatch hooks in one keyed batch reach the parent" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  printf -- '---\nname: a\ndescription: stale desc\n---\nbody\n' > memory/a.md
  printf -- '- [A](a.md) — old hook\n' > memory/MEMORY.md

  abs="$PWD/memory/MEMORY.md"
  pre "$abs" a1
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md

  # index-sync-post.sh fires first, keyed a1: a.md's hook text changed, so it
  # relays "reset frontmatter to match MEMORY.md" to the a1 marker — and still
  # emits its own copy, since "in addition to, not instead of" is unaffected
  # by this defect.
  run sync_feed a1
  [ "$status" -eq 0 ]
  [[ "$output" == *"reset frontmatter to match MEMORY.md"* ]]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new hook"' ]

  # index-compose.sh fires second, same batch, same key: it splices ddaanet's
  # unspliced bullet into the root index and relays "recomposed tier pointers"
  # to the SAME a1 marker, truncating whatever sync just staged there.
  run feed a1
  [ "$status" -eq 0 ]
  [[ "$output" == *"recomposed tier pointers"* ]]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  marker=$(gitlore_relay_marker_file memory a1)
  [ -f "$marker" ]

  # The unkeyed, parent-side run that drains the marker. It needs its own
  # baseline and a real change of its own to reach the drain at all —
  # composition itself finds nothing new to splice, since ddaanet's bullet is
  # already in — the same shape "an unkeyed compose run with no report of its
  # own still emits the relay" (above) uses.
  pre "$abs"
  seed_root_fact "q.md" "another project fact"
  run feed
  [ "$status" -eq 0 ]
  json="$output"
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore-relay agent a1"* ]]
  [[ "$output" == *"reset frontmatter to match MEMORY.md"* ]]
  [[ "$output" == *"recomposed tier pointers"* ]]
  [ ! -f "$marker" ]
}

# Item 3.1 slice 4, Group A (item-3-1-s2-code-review.md F5). `mkdir` on the
# marker path makes gitlore_relay_write's redirect fail with "Is a directory"
# — no permission bits involved, so no root guard and nothing to restore.
# Measured by hand-run today: the hook exits 1 with EMPTY stdout, so the
# subagent's own compose report dies along with the relay it could not stage.
# A relay failure must cost only the relay, never the hook's own report.
@test "a failed relay write leaves the subagent's own report intact" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  squat=$(gitlore_relay_marker_file memory a1)
  mkdir "$squat"
  pre "$PWD/memory/MEMORY.md" a1
  seed_root_fact "p.md" "a project fact"
  # `--separate-stderr`: the failing redirect inside gitlore_relay_write prints
  # "Is a directory" on stderr, and a merged capture would put that line ahead
  # of the JSON — so the jq parse below would fail on a hook that survived and
  # reported exactly as this case requires.
  run --separate-stderr feed a1
  [ "$status" -eq 0 ]
  run jq -r '.systemMessage' <<<"$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recomposed tier pointers"* ]]
  rmdir "$squat"
}

# Item 3.1 slice 5 (item-3-1-s4-code-review.md §1). Slice 4 stopped a failed
# relay write from taking the hook down and in doing so traded a loud failure
# for a silent one: the parent loses the report and nobody — not the parent,
# not the user, not the acting subagent — learns it existed. The fix appends
# a not-staged line to additionalContext specifically: per the subagent-
# confinement probe, systemMessage never leaves the subagent's own JSONL,
# while additionalContext is what the acting model narrates unprompted — the
# only path by which the fact can reach the parent at all, since the actor
# has to carry it there itself.
@test "a failed relay write tells the subagent it was not staged" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  squat=$(gitlore_relay_marker_file memory a1)
  mkdir "$squat"
  pre "$PWD/memory/MEMORY.md" a1
  seed_root_fact "p.md" "a project fact"
  # `--separate-stderr`: the failing redirect inside gitlore_relay_write prints
  # "Is a directory" on stderr, and a merged capture would put that line ahead
  # of the JSON — so the jq parses below would fail on a hook that survived
  # and reported exactly as this case requires.
  run --separate-stderr feed a1
  [ "$status" -eq 0 ]
  json="$output"
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recomposed tier pointers"* ]]
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$json"
  [ "$status" -eq 0 ]
  # jq -r prints the literal string "null" for an absent key — rule that out
  # before refuting anything on the channel's contents.
  [ "$output" != "null" ]
  [[ "$output" == *"could not be staged for the parent session"* ]]
  rmdir "$squat"
}

# The companion to the case above, over the SAME squat: an unkeyed run. This
# is the case that pins what `-type f` in gitlore_relay_drain is actually
# for — not framing a non-marker into the parent's report and not removing
# it — rather than for the abort a fix to §6 (below) would stop it causing.
@test "an unkeyed run leaves a non-marker alone" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  squat=$(gitlore_relay_marker_file memory a1)
  mkdir "$squat"
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  # `--separate-stderr` for the reason the keyed cases above give: this
  # fixture's whole point is a path that produces diagnostics, and $output has
  # to mean the hook's own report and nothing else.
  run --separate-stderr feed
  [ "$status" -eq 0 ]
  [ -d "$squat" ]
  # Over the whole JSON, not one jq-extracted channel: the unkeyed fold puts
  # the framing line on BOTH systemMessage and additionalContext, so a
  # refutation scoped to either one alone would miss the other.
  [[ "$output" != *"gitlore-relay agent a1"* ]]
  # The paired positive over the same capture, and it is not left to the
  # sibling case: the refutation above is satisfied by an EMPTY $output too,
  # and this hook emits nothing at all when its compose report is empty — so
  # without this line a regression that silenced the report would make the
  # refutation vacuous rather than red. Placed after it, not before, so a run
  # that breaks both reports the refutation, which is what this case is for.
  [[ "$output" == *"recomposed tier pointers"* ]]
  rmdir "$squat"
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
