#!/usr/bin/env bats
# The compose gate's checks on a merged root index — duplicates, welds,
# interleaved lines, a leftover prefix, a dangling pointer — and staging with
# no root index at all. Split out of resolve_compose.bats. Also the refusal of
# a merge whose files the merger left holding conflict markers.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# The helper below runs `run` in the test's own shell; SC2030/SC2031 are false
# positives across @test bodies.
# shellcheck disable=SC2030,SC2031
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

  run resolve_gate
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

  run resolve_gate
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

  run resolve_gate
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

  run resolve_gate
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

  run resolve_gate
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
  git -C memory -c user.email=t@t -c user.name=t commit -q -m "No root index"
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  commit_sections "memory: record the org fact"
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

# A memory-store merge, prepared and not yet synthesized. `live` is checked out
# holding LIVE.md, and the merge brings the pending HEAD_SIDE.md in; both sides
# branch from a commit holding git-conflicts.md, which documents conflict markers
# and which the merge leaves alone. Sets nothing: callers read the store.
prepare_memory_merge_with_marker_doc() {
  make_parent_with_memory
  printf '%s\n' 'A conflict leaves these lines in the file:' '' \
    '<<<<<<< HEAD' 'ours' '=======' 'theirs' '>>>>>>> live' \
    > memory/git-conflicts.md
  git -C memory add -A
  git -C memory -c user.email=t@t -c user.name=t commit -q -m "Document conflict markers"
  git -C memory update-ref refs/heads/live HEAD
  make_diverged_head_vs_live memory
  echo parent > parent-file
  git add parent-file
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  run resolve_gate
  [ "$status" -ne 0 ]
  [ -f "$(gitlore_merge_state_file memory)" ]
}

# What a merger leaves behind when it does not resolve a conflict: markers in
# the file at $1 (a path under the store at $2), staged by explicit path as
# agents/memory-merger.md has it.
leave_conflict_markers_in() {
  printf '%s\n' 'before' '<<<<<<< HEAD' 'ours' '=======' 'theirs' '>>>>>>> live' 'after' \
    > "$2/$1"
  git -C "$2" add -- "$1"
}

@test "a memory merge whose merger left conflict markers in a changed file is not committed" {
  prepare_memory_merge_with_marker_doc
  mem_before=$(git -C memory rev-parse HEAD)
  leave_conflict_markers_in LIVE.md memory

  run --separate-stderr run_stub_synth memory
  # The refusal first: today the merge lands with the markers in it.
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"LIVE.md"* ]]
  [ -f "$(gitlore_merge_state_file memory)" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]

  # Prepared, not abandoned: a synthesis without the markers lands.
  printf '%s\n' 'resolved' > memory/LIVE.md
  git -C memory add -A
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]
  git -C memory rev-parse -q --verify HEAD^2 >/dev/null
  [ "$(git -C memory show HEAD:LIVE.md)" = "resolved" ]
}

@test "a tier merge whose merger left conflict markers in a changed file is not committed" {
  prepare_tier_merge_with_new_lines
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  mem_before=$(git -C memory rev-parse HEAD)
  leave_conflict_markers_in "marked file.md" memory/ddaanet

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"marked file.md"* ]]
  [ -f "$(gitlore_merge_state_file memory/ddaanet)" ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
  # Refused before composing: root's index holds nothing of a merge not landed.
  [ -z "$(git -C memory status --porcelain -- MEMORY.md)" ]

  rm "memory/ddaanet/marked file.md"
  git -C memory/ddaanet add -A
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
}

@test "conflict-marker text in a file the merge did not change does not block the merge" {
  prepare_memory_merge_with_marker_doc
  mem_before=$(git -C memory rev-parse HEAD)
  printf 'clean\n' > memory/LIVE.md
  git -C memory add -A

  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$mem_before" ]
  run ! git -C memory rev-parse -q --verify MERGE_HEAD
  # The guard file still holds the marker text, so the pass is not vacuous.
  grep -q '^<<<<<<< HEAD$' memory/git-conflicts.md
  [ -z "$(git -C memory status --porcelain)" ]
}

# The conflict git itself left, in a path the merger never staged: the
# continuation's own `git add -A` is what would mark it resolved. Run directly,
# since run_stub_synth takes a side and stages for the merger.
@test "a conflicted file the merger never staged is not committed" {
  make_parent_with_memory
  (
    cd memory || exit 1
    printf 'head side\n' > CONF.md
    git add CONF.md
    git -c user.email=t@t -c user.name=t commit -q -m "Pending commit"
  )
  advance_branch_with_file memory live CONF.md "live side" "Live commit"
  echo parent > parent-file
  git add parent-file
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  run resolve_gate
  [ "$status" -ne 0 ]
  [ "$(jq -r '.conflicted_files[]' "$(gitlore_merge_state_file memory)")" = "CONF.md" ]
  [ -n "$(git -C memory ls-files -u -- CONF.md)" ]
  mem_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"CONF.md"* ]]
  [ -f "$(gitlore_merge_state_file memory)" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

# What a clean synthesis routinely holds: a path it deleted, and a markdown hard
# line break. Neither is a conflict marker.
@test "a clean synthesis that deletes a file and keeps a hard line break lands" {
  prepare_memory_merge_with_marker_doc
  printf 'clean  \nline\n' > memory/HEAD_SIDE.md
  git -C memory rm -q -- LIVE.md
  git -C memory add -- HEAD_SIDE.md
  [ "$(git -C memory diff --cached --name-status HEAD | sort)" = "$(printf 'A\tHEAD_SIDE.md\nD\tLIVE.md')" ]

  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]
  git -C memory rev-parse -q --verify HEAD^2 >/dev/null
  run ! git -C memory cat-file -e HEAD:LIVE.md
}
