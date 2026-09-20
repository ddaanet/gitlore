#!/usr/bin/env bats
# The compose gate's checks on a merged root index — duplicates, welds,
# interleaved lines, a leftover prefix, a dangling pointer — and staging with
# no root index at all. Split out of resolve_compose.bats.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/stub-synth
load helpers/resolve-compose

@test "a duplicate in the merged root index keeps the merge unlanded" {
  make_parent_with_memory
  diverge_memory_with_index '# Memory Index

- [P](p.md) — one
- [P again](p.md) — two'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  mem_before=$(git -C memory rev-parse HEAD)
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/MEMORY.md: duplicate pointer path p.md"* ]]
  [ -f "$(gitlore_merge_state_file memory)" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "a memory-root merge whose merged index welds a line is not committed" {
  make_parent_with_memory
  diverge_memory_with_index '# Memory Index

- [A](a.md) — a- [B](b.md) — b'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  mem_before=$(git -C memory rev-parse HEAD)
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/MEMORY.md: line "*" welds two pointer bullets"* ]]
  [ -f "$(gitlore_merge_state_file memory)" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "an interleaved line in the merged root index keeps the merge unlanded" {
  make_parent_with_memory
  # The stray line is what reaches the check, and it reaches it because
  # gitlore_index_merge declines a side that carries one: the entry-wise pass
  # rebuilds the bullet block from paths, so a line carrying no path has
  # nowhere to land. Declined, git's line-wise result stands with the line
  # intact, for gitlore_compose_check_index to find.
  diverge_memory_with_index '# Memory Index

- [P](p.md) — one
Stray line
- [Q](q.md) — three'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  mem_before=$(git -C memory rev-parse HEAD)
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/MEMORY.md: interleaved non-bullet line"* ]]
  [ -f "$(gitlore_merge_state_file memory)" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "a memory-root merge with only a leftover root prefix commits uncomposed" {
  make_parent_with_memory
  diverge_memory_with_index '# Memory Index

- [Old fact](gone/x.md) — a tier that is no longer mounted'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]
  all="${output}${stderr}"
  [[ "$all" == *"committed uncomposed"* ]]
  [[ "$all" == *"gone/x.md"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
}

@test "a dangling pointer in the merged index is reported, not repaired" {
  make_parent_with_memory
  diverge_memory_with_index '# Memory Index

- [Gone](gone.md) — the file this names is not there'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]
  all="${output}${stderr}"
  [[ "$all" == *"gone.md names no file in the memory store"* ]]
  [[ "$all" == *"Nothing was rewritten or deleted"* ]]

  # Reported only: the line survives into the commit and no file was created.
  [[ "$(git -C memory show HEAD:MEMORY.md)" == *"- [Gone](gone.md)"* ]]
  [ ! -e memory/gone.md ]
}

@test "a tier merge on a store with no root index commits, reports, and stages the gitlink" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  # A store migrated from an auto-memory dir that held no MEMORY.md: no root
  # index at all. Composition tolerates that; the continuation's staging step
  # must too.
  git -C memory rm -q MEMORY.md
  GITLORE_MEMORY_COMMIT=1 git -C memory -c user.email=t@t -c user.name=t commit -q -m "No root index"
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  push_tier_fact ddaanet "- [their fact](t.md) — theirs" >/dev/null

  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  tier_before=$(git -C memory/ddaanet rev-parse HEAD)

  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [org fact](f.md) — ours\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
[[ "$stderr" == *"no MEMORY.md"* ]]

  # The tier merge landed, and the moved gitlink is staged in the root store.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$tier_before" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ ! -f memory/MEMORY.md ]
}
