#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/commit-memory
load helpers/tier-fixtures

# A store mid-merge meets the merge directive, not the summary refusal: the
# summary's own refusals are in commit_memory_summary.bats, the rest of the
# entry point's behaviour in commit_memory.bats.

@test "a store mid-merge is answered with the merge directive, not a summary refusal" {
  # A prepared merge makes the store dirty by construction and so the
  # summary screen is what this shape could reach first — and it would put a
  # merge both of whose sides are already approved (D49) in front of the user as
  # a summary to draft. The dirty file added after the preparation is what keeps
  # a screen in play: without it the sync's own guard would speak whether or not
  # the screen is ordered behind one.
  make_parent_with_memory
  wire_memory_origin
  make_diverged_head_vs_live memory
  # The commit path prepares no merge; /gitlore:merge does.
  CLAUDECODE=1 run --separate-stderr merge_gate
  [ "$status" -eq 1 ]
  [ -f "$(gitlore_merge_state_file memory)" ]   # the store is mid-merge
  echo more > memory/notes2.md
  head_before=$(git -C memory rev-parse HEAD)

  # A summary the section check refuses (it names no mounted store), so the
  # merge directive can only come from the guard running ahead of that check.
  CLAUDECODE=1 run --separate-stderr commit_with "== nosuchtier ==
memory: add notes"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory merge prepared"* ]]
  [[ "${output}${stderr}" != *"/gitlore:commit"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ -z "$(claude_files)" ]
}

@test "a tier mid-merge is answered with the merge directive, not a summary refusal" {
  # The sibling of the root-store case above, with a tier's own divergence in
  # place of root's. commit-memory.sh guards every mounted tier as well as the
  # root, ahead of the summary refusals: a tier holding a prepared merge is owed
  # that guard's directive, not a refusal that would not help, since the guard
  # refuses on the merge regardless.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live
  advance_branch_with_file "memory/ddaanet" live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  commit_sections "memory: add notes"

  # The commit path prepares no merge; /gitlore:merge does.
  CLAUDECODE=1 run --separate-stderr merge_gate
  [ "$status" -eq 1 ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]   # the tier is mid-merge
  echo more > memory/notes2.md
  head_before=$(git -C memory rev-parse HEAD)

  # A summary the section check refuses (it names no mounted store), so the
  # merge directive can only come from the guard running ahead of that check.
  CLAUDECODE=1 run --separate-stderr commit_with "== nosuchtier ==
memory: add notes"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory merge prepared"* ]]
  [[ "${output}${stderr}" != *"/gitlore:commit"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}
