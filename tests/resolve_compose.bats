#!/usr/bin/env bats
# Composition at the merge continuation.
#
# A landed merge is the one write path into a memory store that no compose
# trigger sees: the PostToolBatch hook fires on an index EDIT, SessionStart on a
# new session. A synthesized index used to sit uncomposed until one of those
# happened to fire; now the continuation composes before it commits, so the
# composed bytes are IN the merge commit.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# Each @test is its own subshell; a per-test `export GITLORE_GIT_RETRY_SCHEDULE`
# is consumed within that same test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/stub-synth
load helpers/resolve-compose

@test "the continuation composes the merged root index into the merge commit" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  # A root-authored tier line with no prior compose: the base is empty, so the
  # merge is a union and the line mirrors down as a fresh add.
  # The project line precedes the tier line, which composition is what reorders:
  # if the committed index is tier-block-first, the pass ran before the commit.
  diverge_memory_with_index '# Memory Index

- [P](p.md) — project
- [T](ddaanet/x.md) — org'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]

  committed=$(git -C memory show HEAD:MEMORY.md)
  [[ "$committed" == *"- [T](ddaanet/x.md) — org"$'\n'"- [P](p.md) — project"* ]]
  # The pass writes the root index only, so the carrier is NOT touched:
  # projecting down would push a line into a second store as a side effect of
  # approving this merge, and the user approved one index.
  run grep -qxF -- '- [T](x.md) — org' memory/ddaanet/MEMORY.md
  [ "$status" -ne 0 ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
}

@test "a tier merge splices its merged carrier lines up into the root index" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  push_tier_fact ddaanet "- [their fact](t.md) — theirs" >/dev/null

  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  mem_before=$(git -C memory rev-parse HEAD)

  # Stand in for the memory-merger sub-agent: synthesize both sides, then add.
  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [org fact](f.md) — ours\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]

  # The merged carrier reached the root index, prefixed.
  grep -qxF -- '- [org fact](ddaanet/f.md) — ours' memory/MEMORY.md
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
  # The tier carries the merge commit; the root carries a bookkeeping commit of
  # its own for the recomposed index and the moved gitlink, so an explicit
  # operation leaves a clean store (D49).
  [ "$(git -C memory rev-parse HEAD)" != "$mem_before" ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory log -1 --format=%s)" = "Update MEMORY.md for ddaanet tier merge." ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
}

# Rewrite the synthesized ddaanet carrier with one pointer twice, so the merged
# index fails the check on the carrier itself.
duplicate_tier_carrier() {
  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [their fact](t.md) — theirs\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A
}

# The head-vs-live counterpart to prepare_tier_merge_with_new_lines: the tier
# diverges from its own local `live`, as tier_divergence.bats's pre-commit
# preparation does, rather than from its remote, so pre-commit prepares the
# merge instead of pre-push.
prepare_tier_merge_head_vs_live() {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT" && return 1
  return 0
}

@test "a tier merge whose merged carrier has a duplicate pointer is not committed" {
  prepare_tier_merge_with_new_lines
  [ "$(jq -r .flavor "$(gitlore_merge_state_file memory/ddaanet)")" = "head-vs-remote" ]
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  mem_before=$(git -C memory rev-parse HEAD)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root-before"
  duplicate_tier_carrier

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md: duplicate pointer path t.md"* ]]
  [ -f "$(gitlore_merge_state_file memory/ddaanet)" ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  cmp -- "$BATS_TEST_TMPDIR/root-before" memory/MEMORY.md
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "a head-vs-live tier merge whose merged carrier has a duplicate pointer is not committed" {
  prepare_tier_merge_head_vs_live
  [ "$(jq -r .flavor "$(gitlore_merge_state_file memory/ddaanet)")" = "head-vs-live" ]
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  mem_before=$(git -C memory rev-parse HEAD)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root-before"
  duplicate_tier_carrier

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md: duplicate pointer path t.md"* ]]
  [ -f "$(gitlore_merge_state_file memory/ddaanet)" ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  cmp -- "$BATS_TEST_TMPDIR/root-before" memory/MEMORY.md
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "a kept refused merge re-emits the continuation directive" {
  prepare_tier_merge_with_new_lines
  duplicate_tier_carrier
  run bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"continue-after-merge"* ]]
}

@test "a re-emitted directive carries the merged-index problem lines" {
  # The refusal prints its problem lines once, to whoever ran the continuation.
  # A session that clears or compacts before the re-synthesis lands meets the
  # merge again through a gate, and the directive that gate emits is the whole
  # briefing the next sub-agent gets — so the lines travel in the state file.
  prepare_tier_merge_with_new_lines
  duplicate_tier_carrier
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md: duplicate pointer path t.md"* ]]

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"continue-after-merge"* ]]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md: duplicate pointer path t.md"* ]]
}

@test "a problem line holding spaces, quotes and a leading dash re-emits byte for byte" {
  # A pointer path is whatever an upstream author wrote, and the problem line
  # quotes it. Carried through the state file it passes a JSON encode and a
  # shell capture, either of which can split it, requote it or eat a leading
  # `-`.
  prepare_tier_merge_with_new_lines
  dup='- [odd](-a "q" b.md) — theirs'
  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n%s\n%s\n' \
    "$dup" "$dup" > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A
  problem='memory/ddaanet/MEMORY.md: duplicate pointer path -a "q" b.md'

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"$problem"* ]]

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 1 ]
  printf '%s\n' "$stderr" | grep -qxF -- "gitlore:   $problem"
}

@test "a merged index that passes the check re-emits without the lines an earlier run recorded" {
  # The lines describe the synthesis the gate last read. Once one passes the
  # check, a merge still prepared for some other reason must not brief the next
  # sub-agent to fix text nobody objects to.
  prepare_tier_merge_with_new_lines
  duplicate_tier_carrier
  run bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]

  hook="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/hooks/commit-msg"
  printf '#!/bin/sh\necho "commit refused by hook" >&2\nexit 1\n' > "$hook"
  chmod +x "$hook"
  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"the merge commit was refused"* ]]

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"continue-after-merge"* ]]
  [[ "$stderr" != *"duplicate pointer path t.md"* ]]
}

@test "a fixed merged carrier lands" {
  prepare_tier_merge_with_new_lines
  duplicate_tier_carrier
  run bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]

  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  merged=$(git -C memory/ddaanet rev-parse HEAD)
  git -C memory/ddaanet rev-parse -q --verify "$merged^2" >/dev/null
  run ! git -C memory/ddaanet rev-parse -q --verify "$merged^3"
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$merged" ]
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
}

@test "a refused tier merge answers an unapproved parent commit with its continuation directive" {
  # The kept merge moves the tier's gitlink, so memory reads dirty with no
  # fresh approval. The merge speaks first: a summary request would put a
  # merge in front of the user, and nothing may commit on top of it anyway.
  prepare_tier_merge_with_new_lines
  duplicate_tier_carrier
  run bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  mem_before=$(git -C memory rev-parse HEAD)
  [ "$(gitlore_commit_msg_freshness memory)" != "yes" ]

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 1 ]
  all="${output}${stderr}"
  [[ "$all" == *"memory merge prepared"* ]]
  [[ "$all" == *"continue-after-merge"* ]]
  [[ "$all" != *"no approved commit summary"* ]]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "a tier merge whose incoming side welds a line is refused, and the split synthesis publishes" {
  # A weld that arrives on the far side of a divergence reaches a synthesis,
  # not a take, so it is re-authored rather than repaired: the entry-wise pass
  # carries the welded line through as one bullet, the gate refuses it, and the
  # split lands and reaches the tier's remote.
  make_parent_with_memory
  git -C memory push -q origin live
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  push_tier_fact ddaanet "- [their fact](t.md) — theirs- [their other](u.md) — also theirs" >/dev/null
  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  git -C memory/ddaanet add -A

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md: line "*" welds two pointer bullets onto one line — u.md"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]

  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [org fact](f.md) — ours\n- [their fact](t.md) — theirs\n- [their other](u.md) — also theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" show live:MEMORY.md > "$BATS_TEST_TMPDIR/published"
  grep -qxF -- '- [their other](u.md) — also theirs' "$BATS_TEST_TMPDIR/published"
  grep -qxF -- '- [their other](ddaanet/u.md) — also theirs' memory/MEMORY.md
}
