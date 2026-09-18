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
DRAIN="$PLUGIN_ROOT/scripts/cc-hooks/relay-drain.sh"

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
# id is meant to steer which baseline this run consumes. `session_id` fixed
# to the same "test-session" sync_feed() carries, so a fixture that gives
# BOTH hooks a real report in one keyed batch (the concurrency case) relays
# under one session rather than two.
feed() {
  local agent="${1:-}"
  jq -n --arg a "$agent" --arg s test-session \
    '{agent_type:"general-purpose", session_id:$s} + (if $a == "" then {} else {agent_id:$a} end)' \
    | bash "$HOOK"
}

# Drives index-sync-post.sh the same way feed() drives index-compose.sh: $1 =
# agent id, optional, same absent-vs-non-empty contract. The hook's own
# pre-hook stash drives propagation, and it reads `session_id` only to key the
# relay and the byte-budget nudge, so a minimal PostToolBatch envelope
# carrying the session is enough. The concurrency case is the one in this
# file that needs the sync hook, alongside the compose hook, in the same
# batch.
sync_feed() {
  local agent="${1:-}"
  jq -n --arg a "$agent" --arg s test-session \
    '{hook_event_name:"PostToolBatch", session_id:$s, tool_calls:[], tool_results:[],
      agent_type:"general-purpose"} + (if $a == "" then {} else {agent_id:$a} end)' \
    | bash "$POST"
}

# Drives relay-drain.sh the same way feed()/sync_feed() drive the other two
# PostToolBatch hooks. $1 = agent id, optional, same absent-vs-non-empty
# contract. $2 = session id, default "test-session" — the same fixed value
# feed()/sync_feed() carry, so a marker either of them staged is found by an
# unkeyed drain run with no override.
drain_feed() {
  local agent="${1:-}" session="${2:-test-session}"
  jq -n --arg a "$agent" --arg s "$session" \
    '{hook_event_name:"PostToolBatch", session_id:$s, tool_calls:[], tool_results:[],
      agent_type:"general-purpose"} + (if $a == "" then {} else {agent_id:$a} end)' \
    | bash "$DRAIN"
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

# --- a report with an empty context half carries no additionalContext key ---
#
# An `additionalContext` present and empty is a block CC injects with nothing in
# it, so the key is omitted instead — the shape index-sync-post.sh emits. No
# report producer reaches that state today: each sets both channels or neither,
# and the drain frames a block per agent whether or not the agent staged any
# context. The tests below drive it through the producer, so the emission is
# pinned by what it is given rather than by what today's producers happen to
# give it.

# A plugin root whose libraries are the real ones with $2 appended to the last
# one the hook under test sources, so a test can hand that hook a report shape
# its producer does not reach. The hook script itself is the real one, invoked
# by its real path — only CLAUDE_PLUGIN_ROOT is redirected. Echoes the root.
# Args: $1 = basename of the library the override is appended to, $2 = shell
# text defining it.
shim_plugin_root() {
  local last="$1" override="$2" root lib
  root="$BATS_TEST_TMPDIR/shim-root"
  mkdir -p "$root/scripts/lib" || return 1
  for lib in "$PLUGIN_ROOT"/scripts/lib/*.sh; do
    printf 'source "%s"\n' "$lib" > "$root/scripts/lib/${lib##*/}" || return 1
  done
  printf '%s\n' "$override" >> "$root/scripts/lib/$last" || return 1
  printf '%s\n' "$root"
}

@test "index-compose.sh omits additionalContext when the context half is empty" {
  root=$(shim_plugin_root index-sync.sh 'gitlore_compose_and_report() {
  GITLORE_COMPOSE_SYSMSG="a report for the user"
  GITLORE_COMPOSE_CTX=""
}')
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  json=$(CLAUDE_PLUGIN_ROOT="$root" feed)
  [ "$(jq -r '.systemMessage' <<<"$json")" = "a report for the user" ]
  run jq -e 'has("hookSpecificOutput")' <<<"$json"
  [ "$status" -eq 1 ]
}

@test "relay-drain.sh omits additionalContext when the context half is empty" {
  root=$(shim_plugin_root index-sync.sh 'gitlore_relay_drain() {
  GITLORE_RELAY_SYSMSG="a relayed report for the user"
  GITLORE_RELAY_CTX=""
}')
  json=$(CLAUDE_PLUGIN_ROOT="$root" drain_feed)
  [ "$(jq -r '.systemMessage' <<<"$json")" = "a relayed report for the user" ]
  run jq -e 'has("hookSpecificOutput")' <<<"$json"
  [ "$status" -eq 1 ]
}

# The paired positive: with a context half, both hooks carry the key. Without
# it the absence above could pass on a hook that never emits the block at all.
@test "both hooks carry additionalContext when the context half is not empty" {
  root=$(shim_plugin_root index-sync.sh 'gitlore_compose_and_report() {
  GITLORE_COMPOSE_SYSMSG="a report for the user"
  GITLORE_COMPOSE_CTX="a report for the model"
}
gitlore_relay_drain() {
  GITLORE_RELAY_SYSMSG="a relayed report for the user"
  GITLORE_RELAY_CTX="a relayed report for the model"
}')
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  json=$(CLAUDE_PLUGIN_ROOT="$root" feed)
  [ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$json")" = "a report for the model" ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$json")" = "PostToolBatch" ]
  json=$(CLAUDE_PLUGIN_ROOT="$root" drain_feed)
  [ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$json")" = "a relayed report for the model" ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$json")" = "PostToolBatch" ]
}

# Reds when the hook's `|| agent_id=""` fallback (line ~44) is removed: jq's
# parse failure then kills the hook under errexit before the stamp is ever
# consumed, so nothing composes and the stamp survives.
@test "an unparseable payload still composes on the unkeyed baseline (fallback proof)" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md"
  [ -f "$(gitlore_compose_stamp_file memory)" ]
  seed_root_fact "p.md" "a project fact"
  # shellcheck disable=SC2016  # $1 expands inside the bash -c script, not here
  run --separate-stderr bash -c 'printf "not json" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ ! -f "$(gitlore_compose_stamp_file memory)" ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  [[ "$output" == *systemMessage* ]]
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
# PostToolBatch. A hook that reads no agent id resolves the bare stamp, so
# this reds on it composing (and reporting, and consuming the bare stamp)
# when it should stay silent and leave that baseline alone.
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
# for the parent's relay-drain.sh to deliver. The subagent still gets its own
# copy on its own channel — "in addition to, not instead of" — so the
# JSON/systemMessage assertions below hold beside the marker.
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
  marker=$(relay_marker_for memory a1)
  [ -f "$marker" ]
  grep -qF 'recomposed tier pointers' "$marker"
}

# Slice 2 (D51 revised): index-compose.sh no longer drains — relay-drain.sh is
# the one drainer now. Replaces the three "unkeyed … folds in" cases and "both
# PostToolBatch hooks in one keyed batch reach the parent", all of which
# pinned the drain-in-each-hook behaviour this slice removes. The
# marker is staged under the session the hook runs in, so any drain returning
# to the hook would consume it, whether scoped to that session (the D51
# shape) or unscoped; a marker under another session survives both and
# asserts nothing.
@test "an unkeyed compose run leaves a marker in place" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_relay_write memory test-session a1 compose "keyed relay sysmsg a1" "keyed relay ctx a1"
  marker=$(relay_marker_for memory a1)
  [ -f "$marker" ]
  pre "$PWD/memory/MEMORY.md"
  seed_root_fact "p.md" "a project fact"
  run feed
  [ "$status" -eq 0 ]
  json="$output"
  run jq -r '.systemMessage' <<<"$json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recomposed tier pointers"* ]]
  [[ "$output" != *"gitlore-relay agent a1"* ]]
  [ -f "$marker" ]
}

# Slice 2, case 1: concurrency at hook level — both hooks report on one keyed
# batch as real separate processes (`&`/`wait`, not sequential calls), and the
# fold happens in relay-drain.sh rather than in either writer, so a lost
# report or a doubled block shows up in the DRAINED output instead of in
# either hook's own.
#
# Launching the two at once is not enough to overlap their writes: the hooks
# do different amounts of work first, and a name chosen by counting the
# reports already there stays green over many runs of an unsynchronised
# version of this case. So a barrier holds each writer at its relay install —
# an `mv` stub that passes every other destination straight through — until
# both have chosen a name and written their temp. The poll is bounded, so a
# hook that never reaches its install costs this case five seconds and a red
# count rather than a hang.
# Ten iterations, fresh per-iteration filenames (a$i.md, shared$i.md, p$i.md)
# rather than a teardown/setup cycle, so a marker relay-drain.sh fails to
# remove this round cannot pollute the count next round with a stale ghost —
# the exact-once assertion would then fail for the wrong reason.
@test "concurrency: both reporting hooks reach relay-drain.sh exactly once per keyed batch" {
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  barrier="$BATS_TEST_TMPDIR/barrier"
  mkdir -p "$fakebin"
  cat > "$fakebin/mv" <<EOF
#!/bin/sh
case "\$2" in
  */gitlore-relay-*)
    : > "$barrier/\$\$"
    n=0
    while [ "\$n" -lt 100 ]; do
      [ "\$(set -- "$barrier"/*; echo "\$#")" -ge 2 ] && break
      sleep 0.05
      n=\$((n + 1))
    done
    ;;
esac
exec /bin/mv "\$@"
EOF
  chmod +x "$fakebin/mv"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    seed_tier_bullet ddaanet "shared$i.md" "a portable fact $i"
    printf -- '---\nname: a%s\ndescription: stale desc %s\n---\nbody\n' "$i" "$i" > "memory/a$i.md"
    printf -- '- [A%s](a%s.md) — old hook %s\n' "$i" "$i" "$i" > memory/MEMORY.md
    abs="$PWD/memory/MEMORY.md"
    pre "$abs" a1
    printf -- '- [A%s](a%s.md) — new hook %s\n' "$i" "$i" "$i" > memory/MEMORY.md

    rm -rf "$barrier"
    mkdir "$barrier"
    PATH="$fakebin:$PATH" sync_feed a1 > "$BATS_TEST_TMPDIR/sync-$i.out" &
    PATH="$fakebin:$PATH" feed a1 > "$BATS_TEST_TMPDIR/compose-$i.out" &
    wait

    run drain_feed "" test-session
    [ "$status" -eq 0 ]
    # Counted on the DECODED channel, never on the raw JSON: jq emits the
    # whole systemMessage as one physical line with its newlines escaped, so
    # `grep -c` over $output counts at most one hit however many blocks the
    # drain wrote — a report relayed twice, the C2 symptom this case exists
    # to catch, would score 1 and pass. Decoding restores one line per block.
    sysmsg=$(jq -r '.systemMessage' <<<"$output")
    n_sync=$(printf '%s\n' "$sysmsg" | grep -c 'reset frontmatter to match MEMORY.md' || true)
    n_compose=$(printf '%s\n' "$sysmsg" | grep -c 'recomposed tier pointers' || true)
    n_frame=$(printf '%s\n' "$sysmsg" | grep -c -- '--- gitlore-relay agent a1 ---' || true)
    [ "$n_sync" -eq 1 ] || { echo "iteration $i: n_sync=$n_sync sysmsg=$sysmsg"; return 1; }
    [ "$n_compose" -eq 1 ] || { echo "iteration $i: n_compose=$n_compose sysmsg=$sysmsg"; return 1; }
    # Two writers, two files, two framed blocks and nothing else. The phrase
    # counts above pin each report present once; this pins that the drain
    # framed nothing beyond them — a third block is a doubled relay even when
    # the two phrase counts still read 1.
    [ "$n_frame" -eq 2 ] || { echo "iteration $i: n_frame=$n_frame sysmsg=$sysmsg"; return 1; }
  done
}

# Slice 2, case 2 (M2): relay-drain.sh delivers on a batch that took no
# baseline at all — no pre-hook stash, no index edit this batch — because it
# is driven by the marker alone, unlike index-sync-post.sh/index-compose.sh.
# This is the fix for M2's "the batch that dispatched the subagent has no
# baseline, so the report waits for an unrelated index edit or the next
# SessionStart". A keyed run must do the opposite: exit at once, emitting
# nothing and touching no file — a subagent never drains.
@test "relay-drain.sh delivers with no baseline (M2); a keyed run exits 0 silently and leaves the files" {
  gitlore_relay_write memory test-session a1 sync "M2 SYSMSG" "M2 CTX"
  marker=$(relay_marker_for memory a1)
  [ -f "$marker" ]

  run drain_feed a1 test-session
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$marker" ]

  run drain_feed "" test-session
  [ "$status" -eq 0 ]
  json="$output"
  sysmsg=$(jq -r '.systemMessage' <<<"$json")
  ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$json")
  [[ "$sysmsg" == *"M2 SYSMSG"* ]]
  # The agent-facing channel too. M2 is about the PARENT learning what its
  # subagent's hook found, and systemMessage reaches the user's terminal while
  # additionalContext is the half the parent model reads — a delivery that
  # dropped it would satisfy the line above and fix nothing.
  [[ "$ctx" == *"M2 CTX"* ]]
  [ ! -f "$marker" ]
}

# Slice 2, case 4: relay-drain.sh scopes its enumeration to its own session —
# the hook-level pin of the library's "a write for session S2 is not drained
# by S1 and survives it" (tests/index_sync.bats).
@test "relay-drain.sh with session S1 leaves an S2 file standing" {
  gitlore_relay_write memory s1 a1 sync "S1 BODY" "S1 CTX"
  gitlore_relay_write memory s2 a2 sync "S2 BODY" "S2 CTX"
  s1_marker=$(relay_marker_for memory a1)
  s2_marker=$(relay_marker_for memory a2)
  [ -f "$s1_marker" ]
  [ -f "$s2_marker" ]

  run drain_feed "" s1
  [ "$status" -eq 0 ]
  json="$output"
  # Through jq rather than a substring match on the raw JSON: the positive is
  # about which CHANNEL carries the body, and jq -r fails on malformed output,
  # so "valid JSON carrying S1's report" is one assertion.
  sysmsg=$(jq -r '.systemMessage' <<<"$json")
  ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$json")
  [[ "$sysmsg" == *"S1 BODY"* ]]
  [[ "$ctx" == *"S1 CTX"* ]]
  # The refutation stays on the raw JSON: S2's body must be absent from every
  # channel, including one this case does not name.
  [[ "$json" != *"S2 BODY"* ]]
  [[ "$json" != *"S2 CTX"* ]]
  [ ! -e "$s1_marker" ]
  [ -f "$s2_marker" ]
}

# Item 3.1 slice 4, Group A (item-3-1-s2-code-review.md F5), adapted for D51
# (revised): the marker's name now carries an epoch and a pid unknown until
# the hook itself runs, so nothing outside its process can `mkdir` the exact
# path in advance the way the pre-revision squat did. Substitute: shadow `mv`
# with a stub that fails only a relay-shaped destination (`*/gitlore-relay-*`)
# and delegates everything else to the real `mv` — so gitlore_relay_write's
# atomic `mv "$marker.tmp" "$marker"` fails while gitlore_compose_and_report's
# own index-writing `mv` (index-compose.sh:702) is untouched, and composition
# still succeeds exactly as this case requires.
@test "a failed relay write leaves the subagent's own report intact" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md" a1
  seed_root_fact "p.md" "a project fact"
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/mv" <<'EOF'
#!/bin/sh
case "$2" in
  */gitlore-relay-*) exit 1 ;;
esac
exec /bin/mv "$@"
EOF
  chmod +x "$fakebin/mv"
  PATH="$fakebin:$PATH" run --separate-stderr feed a1
  [ "$status" -eq 0 ]
  run jq -r '.systemMessage' <<<"$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recomposed tier pointers"* ]]
}

# Item 3.1 slice 5 (item-3-1-s4-code-review.md §1), same mv-stub substitution
# as the case above. Slice 4 stopped a failed relay write from taking the hook
# down and in doing so traded a loud failure for a silent one: the parent
# loses the report and nobody — not the parent, not the user, not the acting
# subagent — learns it existed. The fix appends a not-staged line to
# additionalContext specifically: per the subagent-confinement probe,
# systemMessage never leaves the subagent's own JSONL, while additionalContext
# is what the acting model narrates unprompted — the only path by which the
# fact can reach the parent at all, since the actor has to carry it there
# itself.
@test "a failed relay write tells the subagent it was not staged" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md" a1
  seed_root_fact "p.md" "a project fact"
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/mv" <<'EOF'
#!/bin/sh
case "$2" in
  */gitlore-relay-*) exit 1 ;;
esac
exec /bin/mv "$@"
EOF
  chmod +x "$fakebin/mv"
  PATH="$fakebin:$PATH" run --separate-stderr feed a1
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
