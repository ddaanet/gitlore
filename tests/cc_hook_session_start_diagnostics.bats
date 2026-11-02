#!/usr/bin/env bats
# SessionStart reports store diagnostics and writes no index: the rule problems
# of gitlore_compose_check (an unmounted manifest tier among them), a pending
# compose naming `gitlore-compose`, and dangling pointers, each from a real
# store state. Every case asserts the store's bytes are unchanged afterwards, and
# pairs the diagnostic with a composed store that gets none. Only literals the
# user or agent acts on are pinned: the file, the tier, the command.
#
# Each @test is its own subshell, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/cc-hook-session-start

# A composed, committed store: one active tier whose carrier and the root agree,
# tier and memory clean. Proved composed, not assumed: the read-only check finds
# nothing to write.
composed_store() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet kept.md "carried by both"
  seed_root_bullet "ddaanet/kept.md" "carried by both"
  gitlore_compose memory
  git -C memory/ddaanet add -A
  git -C memory/ddaanet commit -q -m "tier fact"
  commit_memory_state
  [ -z "$(gitlore_compose_pending memory)" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

# Every byte a compose could write, and the state around it.
store_bytes() {
  cat memory/MEMORY.md memory/ddaanet/MEMORY.md memory/.gitlore-tiers
  git -C memory status --porcelain
  git -C memory/ddaanet status --porcelain
  git -C memory/ddaanet rev-parse HEAD
}

# Run SessionStart over the store as it stands; $hook_json keeps its output past
# the later `run`s, and $sys / $ctx are the two channels.
session_start_over_store() {
  enable_gitlore
  export GITLORE_LAUNCHED=1
  bytes_before=$(store_bytes)
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  hook_json="$output"
  sys=$(jq -r '.systemMessage // ""' <<<"$hook_json")
  ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$hook_json")
  [ "$(store_bytes)" = "$bytes_before" ]
}

@test "a composed store gets no diagnostic and keeps the in-sync line" {
  composed_store
  session_start_over_store
  [ "$sys" = "gitlore: memory ready." ]
  [[ "$ctx" != *"gitlore-compose"* ]] || false
}

@test "a manifest naming an unmounted tier is reported by tier name" {
  composed_store
  printf 'ddaanet\nghost\n' > memory/.gitlore-tiers
  commit_memory_state
  session_start_over_store
  assert_report_on_both_channels 'ghost'
  [[ "$sys" == *"memory ready"* ]] || false
}

@test "a duplicate pointer in the root index is reported by file" {
  composed_store
  seed_root_bullet "ddaanet/kept.md" "again"
  commit_memory_state
  session_start_over_store
  [[ "$sys" == *"MEMORY.md"* ]] || false
  [[ "$sys" == *"ddaanet/kept.md"* ]] || false
  [[ "$sys" == *"memory ready"* ]] || false
}

@test "a non-bullet line inside the bullet region is reported by file" {
  composed_store
  printf '\nSome interleaved prose\n\n' >> memory/MEMORY.md
  # A real file, so the file name cannot come from the dangling report. The
  # pending report also prints MEMORY.md, so the negative is what excludes it:
  # a refused store names no compose remedy, a pending one does.
  printf 'x\n' > memory/kept2.md
  seed_root_bullet "kept2.md" "after the prose"
  commit_memory_state
  session_start_over_store
  [[ "$sys" == *"MEMORY.md"* ]] || false
  [[ "$sys" != *"gitlore-compose"* ]] || false
  [[ "$sys" == *"memory ready"* ]] || false
}

@test "a root bullet with an unknown prefix is reported by its path" {
  composed_store
  mkdir -p memory/removed_tier
  printf 'x\n' > memory/removed_tier/orphan.md
  seed_root_bullet "removed_tier/orphan.md" "leftover"
  commit_memory_state
  session_start_over_store
  [[ "$sys" == *"removed_tier/orphan.md"* ]] || false
  [[ "$sys" == *"memory ready"* ]] || false
}

@test "a carrier-only deletion is a pending compose naming the carrier and gitlore-compose" {
  composed_store
  sed -i.bak '/kept\.md/d' memory/ddaanet/MEMORY.md && rm memory/ddaanet/MEMORY.md.bak
  # The fixture holds a real pending compose, not a composed store.
  [ -n "$(gitlore_compose_pending memory)" ]
  session_start_over_store
  assert_report_on_both_channels 'gitlore-compose'
  [[ "$ctx" == *"ddaanet/MEMORY.md"* ]] || false
}

@test "a root line added outside a session is a pending compose naming the carrier and gitlore-compose" {
  composed_store
  printf -- '---\nname: authored\ndescription: ""\n---\n\nbody\n' > memory/ddaanet/authored.md
  seed_root_bullet "ddaanet/authored.md" "written in the root index"
  [ -n "$(gitlore_compose_pending memory)" ]
  session_start_over_store
  [[ "$ctx" == *"gitlore-compose"* ]] || false
  [[ "$ctx" == *"ddaanet/MEMORY.md"* ]] || false
}

@test "a refused store that also holds a dangling pointer reports both" {
  composed_store
  printf 'ddaanet\nghost\n' > memory/.gitlore-tiers
  seed_root_bullet "gone.md" "stale line"
  commit_memory_state
  session_start_over_store
  [[ "$sys" == *"ghost"* ]] || false
  [[ "$sys" == *"gone.md"* ]] || false
}

@test "a dangling root line of an unmounted manifest tier names no carrier" {
  composed_store
  printf 'ddaanet\nghost\n' > memory/.gitlore-tiers
  seed_root_bullet "ghost/x.md" "left by a hand removal"
  commit_memory_state
  session_start_over_store
  # "names no file" and the fix: the rule report names the path as well.
  [[ "$sys" == *"ghost/x.md names no file in the memory store — delete its line from memory/MEMORY.md"* ]] || false
  [[ "$sys" != *"ghost/MEMORY.md"* ]] || false
}

@test "a registered tier with no checkout gets its notice and no edit or compose directive" {
  composed_store
  # A dangling project line, so a silent dangling report cannot pass the negatives.
  seed_root_bullet "gone.md" "stale line"
  commit_memory_state
  unmaterialize_tier ddaanet
  session_start_over_store
  [ ! -e memory/ddaanet/MEMORY.md ]
  [[ "$sys" == *"tier 'ddaanet' could not be checked out"* ]] || false
  [[ "$ctx" == *"tier 'ddaanet' could not be checked out"* ]] || false
  [[ "$ctx" == *"do not delete"* ]] || false
  [[ "$sys" == *"gone.md names no file"* ]] || false
  [[ "$sys" != *"ddaanet/kept.md"* ]] || false
  [[ "$ctx" != *"ddaanet/kept.md"* ]] || false
  [[ "$sys" != *"gitlore-compose"* ]] || false
  [[ "$ctx" != *"gitlore-compose"* ]] || false
}

@test "a clean tier left off its pin is not put back by the diagnostics" {
  composed_store
  strand_live_ahead_of_pin ddaanet
  git -C memory/ddaanet checkout -q --detach live
  # The pin loop leaves the tier where it is, so only a diagnostic can move it.
  git -C memory config submodule.ddaanet.update none
  session_start_over_store
}
