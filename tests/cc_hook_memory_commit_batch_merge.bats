#!/usr/bin/env bats
# What memory-commit-batch.sh says when a merge is in play — in the memory
# store itself or in one of its mounted tiers. The rest of the hook's arms are
# in cc_hook_memory_commit_batch.bats.

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/tier-fixtures
load helpers/cc-hook-memory-commit-batch

@test "a commit that landed but could not advance live hands over the merge directive, not a re-approval" {
  # The commit consumes the approval before the `HEAD:live` fast-forward is
  # refused, so there is no summary left to re-present, only the prepared merge
  # to act on — and nothing for a later batch to retry, since the commit is made.
  make_parent_with_memory
  advance_branch_with_file memory live LIVE.md live-only "Diverging commit on live"
  echo dirty > memory/notes.md
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"
  head_before=$(git -C memory rev-parse HEAD)

  CLAUDECODE=1 run run_batch
  [ "$status" -eq 0 ]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"Reason:"* ]]
  [[ "$agent" == *"memory merge prepared"* ]]
  [[ "$agent" != *"no longer covers"* ]]
  # Neither of the other two branches' claims: this commit DID run, its approval
  # is NOT preserved, and no retry will repeat it. Without these the arm is
  # indistinguishable from the transient-retry one, which asserts all three.
  [[ "$agent" == *"the memory commit landed"* ]]
  [[ "$agent" != *"retries by itself"* ]]
  [[ "$agent" != *"approved summary preserved"* ]]
  [ "$(git -C memory rev-parse HEAD)" != "$head_before" ]
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
  [ -f "$(gitlore_commit_trigger_file memory)" ]
}

@test "the batch after that one re-emits the merge directive instead of asking for a summary" {
  # That commit consumed the approval and its fast-forward left a prepared merge,
  # whose checkout makes the store dirty again — so the next batch arrives with a
  # trigger, a dirty store and nothing approved: exactly the shape the
  # missing-summary screen answers. Answering it would put a merge both of whose
  # sides are already approved (D49) in front of the user as a summary to draft,
  # and the summary would not help — the guard refuses on the merge regardless.
  make_parent_with_memory
  advance_branch_with_file memory live LIVE.md live-only "Diverging commit on live"
  echo dirty > memory/notes.md
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"

  CLAUDECODE=1 run run_batch            # setup: the landed-then-failed arm above
  [ "$status" -eq 0 ]
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
  [ -f "$(gitlore_merge_state_file memory)" ]   # the store is mid-merge
  [ -n "$(git -C memory status --porcelain)" ]

  CLAUDECODE=1 run run_batch
  [ "$status" -eq 0 ]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"memory merge prepared"* ]]
  [[ "$agent" == *"prepared merge"* ]]
  # The screen this batch must not reach, and its two giveaways.
  [[ "$agent" != *"no approved summary exists yet"* ]]
  [[ "$agent" != *blockquote* ]]
  # Nothing consumed and nothing minted: the guard's report-only arms leave both
  # the store and the (absent) approval as they stand, and the trigger is what
  # lets the batch after the merge lands commit without a re-trigger.
  [ -f "$(gitlore_commit_trigger_file memory)" ]
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
}

@test "a tier's prepared merge hands over the merge directive, not a re-approval request" {
  # A tier diverged from its own live prepares a head-vs-live merge in the
  # tier's gitdir, not the root store's, so the post-run screen reads both. A
  # root-only read answers false here, and the merge's checkout into the tier's
  # worktree outdates the leftover approval, so the batch takes the freshness
  # arm instead — which drops $out, withholding the directive the guard produced
  # and returning a merge both of whose sides are already approved (D49) as a
  # summary to re-present.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live
  advance_branch_with_file "memory/ddaanet" live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"
  head_before=$(git -C memory rev-parse HEAD)

  CLAUDECODE=1 run run_batch          # first batch: prepares the tier merge
  [ "$status" -eq 0 ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]

  CLAUDECODE=1 run run_batch
  [ "$status" -eq 0 ]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"memory merge prepared"* ]]
  [[ "$agent" == *"prepared merge"* ]]
  [[ "$agent" != *"no longer covers"* ]]
  user="$(echo "$output" | jq -r '.systemMessage // ""')"
  [ "$user" != "gitlore: memory commit deferred — the approved summary no longer covers the store, approval needed again" ]
  [ -f "$(gitlore_commit_trigger_file memory)" ]
  [ -f "$(gitlore_commit_msg_file memory)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "a tier mid-merge with no approval is not met with a request for a summary" {
  # Same divergence as above, but with the approval gone before the batch that
  # matters, which is the shape the pre-run "no approval yet" screen answers. It
  # reads the tiers for the same reason: against the root alone it misses the
  # tier's merge and asks the user to draft a summary for content both sides of
  # that merge already approved.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live
  advance_branch_with_file "memory/ddaanet" live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md
  printf 'memory: record notes\n' > "$(gitlore_commit_msg_file memory)"
  : > "$(gitlore_commit_trigger_file memory)"

  CLAUDECODE=1 run run_batch          # first batch: prepares the tier merge
  [ "$status" -eq 0 ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  rm -f "$(gitlore_commit_msg_file memory)"

  CLAUDECODE=1 run run_batch
  [ "$status" -eq 0 ]
  agent="$(echo "$output" | ctx)"
  [[ "$agent" == *"memory merge prepared"* ]]
  [[ "$agent" != *"no approved summary exists yet"* ]]
  [[ "$agent" != *blockquote* ]]
  [ -f "$(gitlore_commit_trigger_file memory)" ]
}
