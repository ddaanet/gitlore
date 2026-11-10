#!/usr/bin/env bats
# The continuation of a tier merge lands the merge in the tier and composes
# nothing. The carrier check that keeps a defective merged carrier from landing
# stays, on the carrier alone. The compose into root runs at the end of the
# gitlore-merge run that follows. A memory-store merge still composes at its
# own continuation.
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
load helpers/merge-memory
load helpers/take-order

# Tier 'ddaanet' with a commit here (recorded in root, unpublished) and a commit
# upstream, so a take prepares a tier merge. The merged carrier then holds a
# line root lacks: the upstream one.
UPSTREAM_LINE='- [up](up.md) — from upstream'

# A published store whose tier has diverged, and the take that prepares the
# tier merge. Leaves the merge prepared in memory/ddaanet.
prepare_diverged_tier_merge() {
  take_base_store
  local_tier_commit_recorded ddaanet local.md
  push_tier_fact ddaanet "$UPSTREAM_LINE" >/dev/null
  if bash "$CMD" >"$BATS_TEST_TMPDIR/prepare.out" 2>&1; then
    echo "the take did not prepare a merge" >&2
    return 1
  fi
  [ -f "$(gitlore_merge_state_file memory/ddaanet)" ] || { echo "no tier merge prepared" >&2; cat "$BATS_TEST_TMPDIR/prepare.out" >&2; return 1; }
}

# What the memory-merger sub-agent leaves: the carrier holding both sides' lines.
# The prepared merge already merges the two appends cleanly, so the synthesis
# only stages it; the carrier is checked to hold both before the test relies on
# it.
synthesize_tier_merge() {
  grep -qxF -- "$UPSTREAM_LINE" memory/ddaanet/MEMORY.md || return 1
  grep -qxF -- '- [local](local.md) — committed here' memory/ddaanet/MEMORY.md || return 1
  git -C memory/ddaanet add -A
}

# The merged carrier with a pointer twice, which fails the carrier check.
duplicate_pointer_carrier() {
  synthesize_tier_merge || return 1
  printf '%s\n' "$UPSTREAM_LINE" >> memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A
}

@test "the continuation of a tier merge leaves root's MEMORY.md as it was, though the merged carrier adds a line root lacks" {
  prepare_diverged_tier_merge
  synthesize_tier_merge
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root-before"
  run grep -qF 'ddaanet/up.md' "$BATS_TEST_TMPDIR/root-before"
  [ "$status" -ne 0 ]

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  # The merge landed in the tier...
  [ "$(git -C memory/ddaanet rev-list --count --merges HEAD -1)" = "1" ]
  git -C memory/ddaanet show HEAD:MEMORY.md | grep -qxF -- "$UPSTREAM_LINE"
  # ...and root's index holds the bytes it held before, not the carrier's line.
  cmp -- "$BATS_TEST_TMPDIR/root-before" memory/MEMORY.md || {
    echo "root MEMORY.md was rewritten by the tier continuation" >&2
    return 1
  }
}

@test "the continuation of a tier merge stages nothing in the root store and commits nothing there" {
  prepare_diverged_tier_merge
  synthesize_tier_merge
  root_head=$(git -C memory rev-parse HEAD)
  [ -z "$(git -C memory diff --cached --name-only)" ]

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-list --count --merges HEAD -1)" = "1" ]
  [ -z "$(git -C memory diff --cached --name-only)" ] || {
    printf 'staged in root: %s\n' "$(git -C memory diff --cached --name-only)" >&2
    return 1
  }
  [ "$(git -C memory rev-parse HEAD)" = "$root_head" ] || {
    printf 'root HEAD moved: %s -> %s\n' "$root_head" "$(git -C memory rev-parse HEAD)" >&2
    return 1
  }
}

@test "passing pin: a merged tier carrier that fails the carrier check is not landed and the merge stays prepared" {
  prepare_diverged_tier_merge
  duplicate_pointer_carrier
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  root_head=$(git -C memory rev-parse HEAD)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root-before"

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"duplicate pointer"* ]]
  [ -f "$(gitlore_merge_state_file memory/ddaanet)" ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ "$(git -C memory rev-parse HEAD)" = "$root_head" ]
  cmp -- "$BATS_TEST_TMPDIR/root-before" memory/MEMORY.md
}

@test "a tier merge landed while root holds a line the old adopt path refused leaves the tier on the merge, not on its pin" {
  prepare_diverged_tier_merge
  synthesize_tier_merge
  pin=$(git -C memory rev-parse :ddaanet)
  # A real compose-check refusal in root: a line prefixed with an unmounted tier.
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  err="$stderr"
  [[ "$err" != *"could not take tier"* ]] || {
    printf 'stderr still refuses the tier'\''s lines:\n%s\n' "$err" >&2
    return 1
  }
  merged=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-list --count --merges "$merged" -1)" = "1" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$merged" ]
  [ "$merged" != "$pin" ] || { echo "tier was put back on its pin $pin" >&2; return 1; }
  [[ "$err" != *"back on the commit the memory store records"* ]]
}

@test "the gitlore-merge run after a tier continuation carries the merged lines into root in one commit recording the tier HEAD" {
  prepare_diverged_tier_merge
  synthesize_tier_merge
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  # The continuation composed and committed nothing: the end of the following
  # run is where root's lines and gitlink are written.
  base=$(git -C memory rev-parse HEAD)
  [ "$(git -C memory log --format=%s -1)" != "Update MEMORY.md for ddaanet tier merge." ] || {
    echo "the continuation already committed the bookkeeping in root" >&2
    return 1
  }
  [ -z "$(git -C memory diff --cached --name-only)" ] || {
    echo "the continuation already staged in root" >&2
    return 1
  }
  run grep -qF 'ddaanet/up.md' memory/MEMORY.md
  [ "$status" -ne 0 ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  grep -qxF -- '- [up](ddaanet/up.md) — from upstream' memory/MEMORY.md
  [ "$(git -C memory rev-list --count "$base..HEAD")" = "1" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "passing pin: the continuation of a memory-store merge composes the merged root index into the merge commit" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  # The project line precedes the tier line; composition is what reorders them,
  # so a committed index with the tier block first shows the compose ran before
  # the commit.
  diverge_memory_with_index '# Memory Index

- [P](p.md) — project
- [T](ddaanet/x.md) — org'

  run resolve_gate
  [ "$status" -ne 0 ]
  [ -f "$(gitlore_merge_state_file memory)" ]
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]

  committed=$(git -C memory show HEAD:MEMORY.md)
  [[ "$committed" == *"- [T](ddaanet/x.md) — org"$'\n'"- [P](p.md) — project"* ]]
  [ -z "$(git -C memory status --porcelain)" ]
}
