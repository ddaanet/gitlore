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
load helpers/index-compose
load helpers/hook-guard
load helpers/divergence-fixtures

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

@test "a capped dangling list tells the agent where the rest surface" {
  # A line collapsed into "… and N more" carries no fix, so the context names
  # how to see it; a list within the cap needs no such line.
  export GITLORE_DANGLING_CAP=1
  pre "$PWD/memory/MEMORY.md"
  seed_root_bullet "gone.md" "stale line"
  run feed
  [ "$status" -eq 0 ]
  ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")
  [[ "$ctx" == *"gone.md names no file"* ]]
  [[ "$ctx" != *"re-runs this report"* ]]

  pre "$PWD/memory/MEMORY.md"
  seed_root_bullet "lost.md" "another stale line"
  run feed
  [ "$status" -eq 0 ]
  ctx=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")
  [[ "$ctx" == *"… and 1 more"* ]]
  [[ "$ctx" == *"Only the first 1 are listed. Every edit to memory/MEMORY.md re-runs this report with the rest."* ]]
}

# D60: a PostToolBatch hook that dies reports instead of ending the turn. A
# stamp the pre-hook left and a later umask, a restore or another user's run
# made unreadable: `was=$(gitlore_compose_stamp_get "$key" < "$stamp")`)
# fails its redirect with status 1, after `[ -f "$stamp" ]` passed.
@test "an unreadable stamp is reported on both channels and exits 0" {
  [ "$(id -u)" -ne 0 ] || skip "root reads a mode-000 file"
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md"
  stamp=$(gitlore_compose_stamp_file memory)
  [ -f "$stamp" ]
  chmod 000 "$stamp"

  run --separate-stderr feed
  assert_hook_died index-compose 1 "not recomposed"
}

# --- a tier's carrier is watched like the root index ---
#
# A line removed from the carrier alone, while root carries it and root at HEAD
# carries it, is restored at batch end. Both tests change ONLY the carrier, so
# the root index and the manifest stamps do not move: the compose below runs on
# the carrier's stamp or not at all.

@test "an Edit of only a tier's MEMORY.md composes at batch end and restores the line" {
  seed_committed_tier_block
  pre "$PWD/memory/ddaanet/MEMORY.md"
  # The pre hook took a baseline for a carrier edit, as it does for the root index.
  [ -f "$(gitlore_compose_stamp_file memory)" ]
  set_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [c](c.md) — last'
  run feed
  [ "$status" -eq 0 ]
  assert_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [b](b.md) — middle' \
    '- [c](c.md) — last'
  # Root is untouched: the restore is carrier-ward only.
  assert_bullets memory/MEMORY.md \
    '- [a](ddaanet/a.md) — first' \
    '- [b](ddaanet/b.md) — middle' \
    '- [c](ddaanet/c.md) — last'
}

@test "a Bash sed on only a tier's MEMORY.md composes at batch end and restores the line" {
  seed_committed_tier_block
  pre Bash
  sed -i.bak '/](b.md)/d' memory/ddaanet/MEMORY.md && rm -f memory/ddaanet/MEMORY.md.bak
  # The fixture really removed the line, so the restore below has work to do.
  run -1 grep -qF '](b.md)' memory/ddaanet/MEMORY.md
  run feed
  [ "$status" -eq 0 ]
  assert_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [b](b.md) — middle' \
    '- [c](c.md) — last'
}

@test "a carrier edit that removes nothing keeps its added line and emits no restore text" {
  seed_committed_tier_block
  pre "$PWD/memory/ddaanet/MEMORY.md"
  [ -f "$(gitlore_compose_stamp_file memory)" ]
  set_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [b](b.md) — middle' \
    '- [c](c.md) — last' \
    '- [d](d.md) — written into the carrier'
  run feed
  [ "$status" -eq 0 ]
  # The added line is reported as an orphan (the positive over this fixture), and
  # the report carries no restore text, which would say "removal".
  ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$output")
  [[ "$ctx" == *"d.md is in the tier but not in the root index"* ]] || false
  [[ "$ctx" != *"removal"* ]] || false
  assert_bullets memory/ddaanet/MEMORY.md \
    '- [a](a.md) — first' \
    '- [b](b.md) — middle' \
    '- [c](c.md) — last' \
    '- [d](d.md) — written into the carrier'
}

@test "a carrier edit in a tier with a prepared merge is not refused and stays as edited" {
  # The tier at `live`, then the merge the gate prepares: the tier holds a staged
  # merge whose carrier edit is the merger's, and it sits off the commit memory
  # records for it. A compose here would refuse (rule 7), so the carrier stamp
  # must leave such a tier out. Same fixture as tests/tier_divergence.bats's
  # prepared-merge case: the two sides touch different files, so it merges clean.
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  commit_sections "memory: record the org fact"
  merge_gate || true
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]

  pre "$PWD/memory/ddaanet/MEMORY.md"
  echo "- [merged](m.md) — the merger's line" >> memory/ddaanet/MEMORY.md
  edited=$(cksum < memory/ddaanet/MEMORY.md)
  run feed
  [ "$status" -eq 0 ]
  # Nothing emitted: no refusal, and no report of any other kind either.
  [ -z "$output" ]
  [ "$(cksum < memory/ddaanet/MEMORY.md)" = "$edited" ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
}

@test "the batch that prepares a tier merge is not refused and leaves the carrier and merge intact" {
  # Same fixture as above, but the pre stamp is taken BEFORE the gate prepares
  # the merge, so the carrier key is in the pre stamp only. A key in one stamp
  # is not a carrier edit: nothing composes, so rule 7 has nothing to refuse.
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  commit_sections "memory: record the org fact"

  pre Bash
  run merge_gate
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  carrier=$(cksum < memory/ddaanet/MEMORY.md)
  run feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cksum < memory/ddaanet/MEMORY.md)" = "$carrier" ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
}
