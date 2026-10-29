#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/tier-fixtures
load helpers/commit-memory

# D70: the commit path never prepares or takes a merge. After committing, each
# committed store's local `live` is fast-forwarded to the new commit; a `live`
# that cannot be is reported, exit 0, pointing at /gitlore:merge or
# /gitlore:push, and the commit stands (exit 0, since it landed).

# A fork is an expected condition, so the report is an agent directive: it
# states the condition and names the next act for the store labelled $1
# (`memory` or `tier '<name>'`). No alarm word: it is not an error and the
# commit did not fail.
assert_divergence_report() {
  local label="$1" lower
  [ "$stderr" = "gitlore: $label committed. Local live has diverged. Run /gitlore:merge to reconcile them, or /gitlore:push to reconcile and publish." ]
  lower=$(printf '%s' "$stderr" | tr '[:upper:]' '[:lower:]')
  [[ "$lower" != *"error"* ]]
  [[ "$lower" != *"fail"* ]]
}

# Nothing is mid-merge in the store at $1: no MERGE_HEAD, no state file.
assert_not_mid_merge() {
  [ -z "$(git -C "$1" rev-parse -q --verify MERGE_HEAD)" ]
  [ ! -e "$(git -C "$1" rev-parse --git-path gitlore-merge-state)" ]
}

@test "a root commit fast-forwards the store's local live" {
  make_parent_with_memory
  head_before=$(git -C memory rev-parse HEAD)
  echo dirty > memory/notes.md

  run --separate-stderr commit_with "== memory ==
memory: add notes"
  [ "$status" -eq 0 ]
  head_after=$(git -C memory rev-parse HEAD)
  [ "$head_after" != "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$head_after" ]
  [[ "$stderr" != *"/gitlore:merge"* ]]
}

@test "a two-store commit fast-forwards each store's live to its own commit" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  echo dirty > memory/notes.md
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md
  tier_before=$(git -C memory/ddaanet rev-parse HEAD)

  run --separate-stderr commit_with "== ddaanet ==
memory: record the tier fact
== memory ==
memory: add notes"
  [ "$status" -eq 0 ]
  tier_after=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$tier_after" != "$tier_before" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$tier_after" ]
  [ "$(git -C memory rev-parse live)" = "$(git -C memory rev-parse HEAD)" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes" ]
}

@test "root live that cannot fast-forward is reported, left in place and nothing merged" {
  make_parent_with_memory
  advance_branch_with_file memory live LIVE.md live-only "Diverging commit on live"
  live_before=$(git -C memory rev-parse live)
  echo dirty > memory/notes.md

  CLAUDECODE=1 run --separate-stderr commit_with "== memory ==
memory: add notes"
  # The commit landed, so the exit is 0; the report is on stderr.
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes" ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
  assert_divergence_report memory
  assert_not_mid_merge memory
}

@test "a tier live that cannot fast-forward is reported by tier, left in place and nothing merged" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  live_before=$(git -C memory/ddaanet rev-parse live)
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md

  CLAUDECODE=1 run --separate-stderr commit_with "== ddaanet ==
memory: record the tier fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet log -1 --pretty=%s)" = "memory: record the tier fact" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$live_before" ]
  assert_divergence_report "tier 'ddaanet'"
  assert_not_mid_merge memory/ddaanet
  assert_not_mid_merge memory
}
