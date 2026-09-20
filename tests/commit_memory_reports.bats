#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/commit-memory

# A compose problem that is committed but not dirty commits and reports rather
# than aborting; the pin guard's own wording, on both the agent and user arms.

@test "a carrier defect in a clean tier commits and reports" {
  # The abort is scoped to a problem-bearing index that IS dirty. A defect
  # already committed inside the tier's own history, with nothing uncommitted
  # in the carrier, reports instead — even though memory itself is dirty from
  # an unrelated root edit.
  committed_carrier_defect_store
  seed_root_bullet "unrelated.md" "an unrelated fact"
  printf -- '---\nname: unrelated\ndescription: ""\n---\n\nbody\n' > memory/unrelated.md

  head_before=$(git -C memory rev-parse HEAD)
  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record an unrelated fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head_before" ]
  [[ "${output}${stderr}" == *"the commit went ahead"* ]]
  [[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: duplicate pointer path shared.md"* ]]
}

@test "a tier dirty only outside its carrier commits and reports" {
  # Same committed carrier defect as above, but the tier's worktree is dirty
  # from a file that is not MEMORY.md — the abort reads dirtiness of the
  # carrier itself, not of the tier as a whole.
  committed_carrier_defect_store
  printf 'a new tier fact\n' > memory/ddaanet/extra.md
  seed_root_bullet "unrelated.md" "an unrelated fact"
  printf -- '---\nname: unrelated\ndescription: ""\n---\n\nbody\n' > memory/unrelated.md

  head_before=$(git -C memory rev-parse HEAD)
  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record an unrelated fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head_before" ]
  [[ "${output}${stderr}" == *"the commit went ahead"* ]]
  [[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: duplicate pointer path shared.md"* ]]
}

# A tier whose committed carrier holds a duplicate pointer, recorded as the
# tier's pin, with the carrier clean. The clean-carrier check is what keeps the
# callers honest: a carrier left dirty turns their commit-and-report case into
# the abort.
committed_carrier_defect_store() {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "hook"
  seed_tier_bullet ddaanet shared.md "hook"
  git -C memory/ddaanet add -A || return 1
  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q -m "carrier: duplicate pointer" || return 1
  commit_memory_state || return 1
  [ -z "$(git -C memory/ddaanet status --porcelain -- MEMORY.md)" ] || {
    echo "committed_carrier_defect_store: the carrier is dirty" >&2
    return 1
  }
}

@test "a root index dirty only outside MEMORY.md commits and reports" {
  # Root's counterpart of the tier case above: a committed root defect with
  # memory dirty from a new fact file reports, because root's MEMORY.md itself
  # carries no changes.
  make_parent_with_memory
  seed_root_bullet "dup.md" "hook"
  seed_root_bullet "dup.md" "hook"
  printf -- '---\nname: dup\ndescription: ""\n---\n\nbody\n' > memory/dup.md
  commit_memory_state
  printf -- '---\nname: unrelated\ndescription: ""\n---\n\nbody\n' > memory/unrelated.md

  head_before=$(git -C memory rev-parse HEAD)
  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record an unrelated fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head_before" ]
  [[ "${output}${stderr}" == *"the commit went ahead"* ]]
  [[ "${output}${stderr}" == *"memory/MEMORY.md: duplicate pointer path dup.md"* ]]
}

@test "a leftover root prefix commits and reports even when root is dirty" {
  # Rule 3 problems carry no file prefix at all, so the attribution helper can
  # never match them to root's file — they report unconditionally, regardless
  # of root's own dirtiness.
  make_parent_with_memory
  seed_root_bullet "gone/x.md" "leftover"

  head_before=$(git -C memory rev-parse HEAD)
  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record a leftover prefix"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head_before" ]
  [[ "${output}${stderr}" == *"root index line 'gone/x.md' has a prefix naming no mounted tier"* ]]
  [[ "${output}${stderr}" == *"the commit went ahead"* ]]
}

@test "a tier holding a merge gitlore did not prepare is not composed into" {
  # The refusal in gitlore_sync_tiers_to_live says nothing was changed. Compose
  # runs ahead of it and writes carrier files, so without a matching guard on
  # the compose side that sentence is false and the projection has already
  # destroyed the tier's approved text. Rule 7 does not cover this: it is
  # reached only when HEAD has moved off the pin, and a hand-run `git merge`
  # leaves HEAD exactly where the memory index records it.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"

  # `--absolute-git-dir`, not a `$(cd … && pwd)` pair: CDPATH glues a directory
  # listing onto the front of such a capture — the hazard every entry point
  # under scripts/ unsets CDPATH for, and which this suite does not.
  gd=$(git -C memory/ddaanet rev-parse --absolute-git-dir)
  git -C memory/ddaanet rev-parse HEAD > "$gd/MERGE_HEAD"

  run bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -eq 1 ]
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — stale hook'
}

@test "a tier moved sideways off its pin aborts the commit" {
  # gitlore_compose_check_pins refuses when a tier's worktree HEAD has moved off
  # the commit the memory store's INDEX records for it (D31, D36): projecting
  # root's text over an unadopted carrier would destroy approved upstream facts.
  # Item 1.2 makes that refusal abort the commit outright, rather than letting
  # the commit's own `add -A` stage the moved gitlink and erase the very
  # condition the refusal fired on. The carrier and the root line disagree as
  # well, so the refusal has real work to withhold rather than being a no-op.
  #
  # Repointed at Item 1.3 slice 2 onto a SIDEWAYS move: an orphan commit shares
  # no history with the pin in either direction (neither ancestor nor
  # descendant), unlike a fast-forward `commit --allow-empty` (which stays a
  # descendant, i.e. ahead) — the sideways case is the one whose wording and
  # `checkout --detach` remedy stay unchanged, which is what this test's
  # assertions below actually pin. The ahead case gets its own test next,
  # "the pin-abort's ahead wording reaches both the agent arm and the user
  # arm".
  #
  # Born-green: today ahead and sideways abort identically, so this cannot go
  # red by writing it — its red is owed to the test review's mutation:
  # implement slice 2's branch WITHOUT the `merge-base --is-ancestor` test
  # (unconditionally, for every off-pin tier). "is checked out at" stays green
  # under that mutation — the ahead wording (index-compose-check.sh:267) carries
  # the same phrase — so what goes red is the negative `!= *"ahead"*` assertion
  # near the end of this case, once every off-pin tier gets the ahead wording
  # instead of the sideways one. Restore the ancestry test afterward.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  git -C memory/ddaanet checkout -q --orphan gitlore-sideways-test
  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge, sideways"
  # The fixture's shape, asserted rather than assumed.
  run ! git -C memory/ddaanet merge-base \
    "$(git -C memory rev-parse ":ddaanet")" HEAD

  head_before=$(git -C memory rev-parse HEAD)
  pin_before=$(git -C memory rev-parse ":ddaanet")
  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  # The unchanged HEAD and the unchanged pin are the assertions this item
  # exists for — the exit code alone would pass against an abort that had
  # already staged the move.
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  assert_bullets memory/ddaanet/MEMORY.md "- [shared](shared.md) — stale hook"
  [ -f "$(gitlore_commit_msg_file memory)" ]
  # The approval survives the abort, so the retry is not refused for a change
  # nobody made. It reads "absent" against a commit that lands and consumes the
  # file. What it cannot see is the abort arm's restamp: this fixture writes
  # nothing before the pin guard, so the tree is no newer than the summary with
  # or without it — "a commit that fails after composing keeps the approval for
  # the retry" is the case where the restamp has an observable.
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
  [[ "$stderr" == *"moved off the commit the memory store records for it"* ]]
  [[ "$stderr" == *"is checked out at"* ]]
  # The wrapper's own sentence, which nothing else in the suite looks at. It
  # names no remedy of its own — $pin_problems can carry tiers with different
  # causes in one abort, so the wrapper points at the per-cause line each
  # branch already printed. That the sideways line is a runnable command stays
  # pinned on the producer, in tests/index_compose_pins.bats.
  [[ "$stderr" == *"Follow the remedy on each line above, then retry the commit"* ]]
  # And not the ahead branch's words: for a sideways tier the return-to-the-pin
  # remedy above is the right one.
  [[ "$stderr" != *"ahead"* ]]
}

@test "the pin-abort's ahead wording reaches both the agent arm and the user arm" {
  # resolve.sh's abort wrapper (gitlore_sync_memory_to_live) embeds
  # gitlore_compose_check_pins' own $pin_problems verbatim in BOTH branches of
  # gitlore_say_for_agent_or_user, so whatever index-compose.sh says for an
  # ahead tier reaches stderr regardless of CLAUDECODE — this fixture proves
  # it for the ahead case, complementing the sideways one above. A
  # fast-forward `commit --allow-empty` stays a descendant of the tier's
  # current HEAD (the pin the memory store still records): ahead, not
  # sideways.
  #
  # The mount leaves the tier no local `live`, so this is the ahead tier whose
  # commits HEAD alone holds — refused where it stands, its remedy the push
  # that puts them where /gitlore:merge can adopt them.
  #
  # What is asserted is what tests/index_compose_pins.bats' ahead-of-pin test
  # asserts, minus the shas: this test's job is that the wording CROSSES the
  # wrapper into both arms, not to re-pin the message's content. Both positives
  # are read off the tier's own report line, because the wrapper's agent arm
  # wraps $pin_problems in remedy prose of its own and a whole-stderr match
  # could be satisfied by that instead.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"
  # The fixture's shape, asserted rather than assumed: a fast-forward
  # `commit --allow-empty` stays a descendant of the commit the memory store
  # still records, i.e. ahead.
  git -C memory/ddaanet merge-base --is-ancestor \
    "$(git -C memory rev-parse ":ddaanet")" HEAD

  # The second run reuses this fixture, so what the first run leaves behind is
  # snapshotted rather than assumed: a first run that stamped the commit-msg
  # file, staged the gitlink or left merge state would make the second run's
  # result mean something other than "the user arm says the same thing".
  pin_before=$(git -C memory rev-parse ":ddaanet")
  tier_head_before=$(git -C memory/ddaanet rev-parse HEAD)
  tier_state_before=$(git -C memory/ddaanet status --porcelain)
  mem_state_before=$(git -C memory status --porcelain)

  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  agent_line=$(printf '%s\n' "$stderr" | grep -F "tier 'ddaanet'")
  [[ "$agent_line" == *"ahead"* ]]
  [[ "$agent_line" == *"leave nothing uncommitted"* ]]
  [[ "$stderr" != *"checkout --detach"* ]]
  # Every remedy the abort prints writes into the store, which the approved
  # summary's freshness is measured against, so the agent arm must not promise
  # the approval survives it.
  [[ "$stderr" != *"still in place"* ]]
  [[ "$stderr" == *"approved again"* ]]

  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head_before" ]
  [ "$(git -C memory/ddaanet status --porcelain)" = "$tier_state_before" ]
  [ "$(git -C memory status --porcelain)" = "$mem_state_before" ]

  unset CLAUDECODE
  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  user_line=$(printf '%s\n' "$stderr" | grep -F "tier 'ddaanet'")
  [[ "$user_line" == *"ahead"* ]]
  [[ "$user_line" == *"leave nothing uncommitted"* ]]
  [[ "$stderr" != *"checkout --detach"* ]]
  # The report line is $pin_problems verbatim, so the two arms carry it
  # unchanged; the arms themselves differ only in the remedy prose around it.
  [ "$user_line" = "$agent_line" ]
  # And the second run really was the other arm: scripts/lib/log.sh branches on
  # CLAUDECODE, which a subagent dispatch sets in the ambient environment, so
  # without a positive read of the user arm's own sentence this test could pass
  # with the agent arm answering twice.
  [[ "$stderr" == *"Open this project in Claude Code"* ]]
}
