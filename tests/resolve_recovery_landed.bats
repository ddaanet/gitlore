#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth
load helpers/tier-fixtures
load helpers/resolve-recovery


@test "recovery: a landed tier merge stages the moved gitlink in the memory store's index" {
  tier_prepare_head_vs_live ddaanet
  pin_before=$(git -C memory rev-parse ":ddaanet")

  # Land directly, bypassing the continuation: MERGE_HEAD clears (git's own
  # post-commit cleanup), the merge-state file does not, and memory's index is
  # still pinned at the pre-merge commit.
  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$landed" != "$pin_before" ]
  # HEAD moves off the landed merge onto a clean ancestor of it — the branch
  # that has to check out the merge again before it can stage anything.
  git -C memory/ddaanet checkout -q --detach live
  # An unapproved edit sitting in the memory worktree while the recovery runs.
  printf 'unapproved\n' > memory/SCRATCH.md

  run --separate-stderr gitlore_guard_stale_merge_state memory/ddaanet
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]
  # The gitlink it moved, and nothing else: `add -- <tier>`, never `add -A`.
  # An over-broad stage here would put unapproved content into the index the
  # next approved memory commit sweeps up. After the pin assertion, so the case
  # still reds on the pin against unchanged code.
  staged_in_memory=$(git -C memory diff --cached --name-only)
  [[ "$staged_in_memory" != *SCRATCH.md* ]]
}

@test "recovery: the branch where HEAD already carries the landed merge stages it too" {
  tier_prepare_head_vs_live ddaanet

  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  # HEAD is left exactly where the commit put it — the OTHER rc-0 branch from
  # the case above, where only the bookkeeping outlived the merge.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ]

  run --separate-stderr gitlore_guard_stale_merge_state memory/ddaanet
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]
}

# A continuation killed right after its own bookkeeping commit, then re-run.
# The pair is already adopted — memory's index already records the tier's
# HEAD — and the tier's merge-state file is left in place (that commit clears
# only the tier's own MERGE_HEAD, never memory's leftover state), so the next
# gate still classifies this as a landed merge to recover. Without the
# short-circuit, gitlore_adopt_recovered_merge composes up again and projects
# the carrier's text over the root-index edit made since.
@test "recovery: adoption is a no-op when the enclosing index already records the tier's HEAD" {
  tier_prepare_head_vs_live ddaanet

  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit
  landed=$(git -C memory/ddaanet rev-parse HEAD)

  # Adopt once, directly, and commit it in memory — exactly what a
  # continuation's own tail does. Calling the adoption directly, rather than
  # through gitlore_recover_landed_merge, leaves the tier's merge-state file
  # untouched for the recovery call below to still find.
  abs=$(cd memory/ddaanet && pwd)
  gitlore_adopt_recovered_merge memory/ddaanet "$abs"
  commit_memory_state "memory: adopt the tier merge"
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]

  # A root-index edit to that tier's own line, made after the pair was
  # adopted — the edit a second up projection would overwrite.
  awk '/^- \[org fact\]/ { sub(/ — .*/, " — edited after adoption"); } { print }' \
    memory/MEMORY.md > "$BATS_TEST_TMPDIR/edited-index"
  cp "$BATS_TEST_TMPDIR/edited-index" memory/MEMORY.md
  grep -qxF -- "- [org fact](ddaanet/f.md) — edited after adoption" memory/MEMORY.md

  run --separate-stderr gitlore_guard_stale_merge_state memory/ddaanet
  [ "$status" -eq 0 ]
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/edited-index"
  git -C memory diff --cached --quiet
}

# BORN-GREEN, unlike the four cases around it. `--show-superproject-working-tree`
# does not by itself distinguish a tier (superproject = an enclosing memory
# store) from the memory root (superproject = the user's own project, which is
# never a memory store just for having one) — so staging must be scoped by an
# explicit predicate: the superproject carries MEMORY.md at its root AND the
# recovered store's own path, relative to that superproject, is NOT the
# superproject's own `submodule.gitlore-memory.path` (both conditions — no
# membership test against `gitlore_tier_paths`, which would only restate what
# `--show-superproject-working-tree` already settled). Staging the memory
# root's own gitlink into the user's project index is the pre-commit hook's job,
# gated by FR11's approval — not this recovery's to do unprompted.
#
# "Nothing staged in the parent repo" held against the code as it stood when
# this case was written, so it characterizes the scope rule rather than proving
# it on its own. Its discriminating proof is the memory-root exclusion clause,
# and the case that isolates that clause is the host-project one below: drop the
# exclusion and THAT case reds, while this one does not.
#
# It no longer reds under a predicate missing the exclusion clause either:
# adoption stages the pair, so a parent with no root MEMORY.md fails
# `add -- MEMORY.md memory` on the pathspec and stages nothing — this case then
# passes for the wrong reason. Read it as a characterization of the memory
# root's scope, not as the clause's pin.
@test "recovery: the same recovery for the memory root stages nothing in the parent repo" {
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]

  GITLORE_MEMORY_COMMIT=1 git -C memory commit -q --no-edit
  landed=$(git -C memory rev-parse HEAD)
  git -C memory checkout -q --detach live

  before=$(git diff --cached --name-only)
  run --separate-stderr gitlore_guard_stale_merge_state memory
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$landed" ]
  [ "$(git diff --cached --name-only)" = "$before" ]
}

