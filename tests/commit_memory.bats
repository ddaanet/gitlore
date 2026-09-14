#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# The spaced-root cases re-root $TMP_REPO inside their own test body.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/tier-fixtures

CMD="$PLUGIN_ROOT/scripts/commit-memory.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

@test "exits 0 when gitlore is not configured" {
  run bash "$CMD" -m "noop"
  [ "$status" -eq 0 ]
}

@test "exits 0 when memory is clean and synced" {
  make_parent_with_memory
  run bash "$CMD"
  [ "$status" -eq 0 ]
}

@test "commit_msg_file resolves to the parent .claude/ path, not the gitdir" {
  make_parent_with_memory
  run gitlore_commit_msg_file memory
  [ "$status" -eq 0 ]
  # The equality is the whole assertion: any path inside a gitdir fails it, so a
  # separate "not under .git/" check could only ever restate it.
  [ "$output" = "$TMP_REPO/.claude/gitlore-memory-message" ]
}

@test "exits 0 in a session-less worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  run bash "$CMD" -m "noop"
  [ "$status" -eq 0 ]
}

@test "refuses dirty memory with no summary, leaving it uncommitted" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  CLAUDECODE=1 run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"approved summary"* ]] || \
    [[ "${output}${stderr}" == *"-m"* ]]
  [ -n "$(git -C memory status --porcelain)" ]   # still dirty, nothing committed
}

@test "-m commits dirty memory and advances live without a parent commit" {
  make_parent_with_memory
  parent_head_before=$(git rev-parse HEAD)
  echo dirty > memory/notes.md

  run bash "$CMD" -m "memory: add notes"
  [ "$status" -eq 0 ]

  # Memory committed and live advanced.
  [ -z "$(git -C memory status --porcelain)" ]
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes" ]
  # The commit-msg IPC file was consumed.
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
  # No parent commit happened.
  [ "$(git rev-parse HEAD)" = "$parent_head_before" ]
}

@test "-F - reads the summary from a heredoc" {
  make_parent_with_memory
  echo dirty > memory/notes.md

  run bash -c "'$CMD' -F - <<'EOF'
memory: from heredoc
EOF"
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: from heredoc" ]
}

@test "exits 1 with merge directive when branch diverged from live" {
  make_parent_with_memory
  # `live` advances behind the detached worktree's back (D17 branch model:
  # `live` is never checked out, so this is plumbing, not a checkout dance).
  advance_branch_with_file memory live LIVE.md live-only "Diverging commit on live"
  echo dirty > memory/notes.md

  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: add notes"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory merge prepared"* ]]
  [[ "${output}${stderr}" == *"flavor=head-vs-live"* ]]
}

@test "-m with no summary operand is a usage error, not a silent exit 1" {
  make_parent_with_memory
  run --separate-stderr bash "$CMD" -m
  [ "$status" -eq 2 ]
  [[ "$stderr" == *usage* ]]
}

@test "commit-memory composes the carrier into the commit it makes" {
  # A carrier whose bullet text disagrees with the root index line that projects
  # onto it. Composition re-texts the carrier line from the root's, so the
  # committed carrier must read "fresh hook"; without a compose on the commit
  # path the store ships "stale hook" to the tier's remote.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"

  run bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -eq 0 ]

  # Exact block, not a present/absent pair: "stale hook" is a variant of
  # "fresh hook", so no single fault could fail a negative on its own.
  git -C memory/ddaanet show HEAD:MEMORY.md > "$BATS_TEST_TMPDIR/carrier.md"
  assert_bullets "$BATS_TEST_TMPDIR/carrier.md" \
    '- [shared](shared.md) — fresh hook'

  # The memory commit records the tier commit that carries the composed carrier,
  # not the one before it — the tier-first ordering, locked against a reshuffle.
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
}

@test "a dirty carrier with a duplicate pointer aborts the memory commit" {
  # A compose refusal in an index file this commit carries changes to aborts:
  # committing it would publish the defect. Refusals elsewhere only report.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  # A fresh mount has no local `live`; one is created so a commit that lands
  # the tier would advance it, giving the "unmoved" assertion something to catch.
  git -C memory/ddaanet branch -f live
  seed_tier_bullet ddaanet shared.md "hook"
  seed_tier_bullet ddaanet shared.md "hook"
  seed_root_bullet "ddaanet/shared.md" "hook"

  head_before=$(git -C memory rev-parse HEAD)
  tier_head_before=$(git -C memory/ddaanet rev-parse HEAD)
  tier_live_before=$(git -C memory/ddaanet rev-parse live)
  carrier_before=$(cat memory/ddaanet/MEMORY.md)
  tier_state_before=$(git -C memory/ddaanet status --porcelain)
  mem_state_before=$(git -C memory status --porcelain)

  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: duplicate pointer path shared.md"* ]]
  [[ "${output}${stderr}" == *"aborted"* ]]
  # The abort replaces the advisory text rather than appending to it.
  [[ "${output}${stderr}" != *"the commit went ahead"* ]]
  [ -n "$(git -C memory/ddaanet status --porcelain -- MEMORY.md)" ]
  [ "$(cat memory/ddaanet/MEMORY.md)" = "$carrier_before" ]
  [ "$(git -C memory/ddaanet status --porcelain)" = "$tier_state_before" ]
  [ "$(git -C memory status --porcelain)" = "$mem_state_before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head_before" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$tier_live_before" ]

  # The user arm aborts too. CLAUDECODE is unset explicitly: a subagent
  # dispatch exports it, and the arm's own sentence proves which arm answered.
  unset CLAUDECODE
  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"aborted"* ]]
  [[ "${output}${stderr}" != *"the commit went ahead"* ]]
  [[ "${output}${stderr}" == *"Open this project in Claude Code"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head_before" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$tier_live_before" ]
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
  # under that mutation — the ahead wording (index-compose.sh:358) carries the
  # same phrase — so what goes red is the negative `!= *"ahead"*` assertion
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
  # pinned on the producer, in tests/index_compose.bats.
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
  # What is asserted is what tests/index_compose.bats' ahead-of-pin test
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
  [[ "$agent_line" == *"discard"* ]]
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
  [[ "$user_line" == *"discard"* ]]
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

@test "a commit that landed a tier and then failed on memory's index retries to completion" {
  # The tier commit moves the tier ahead of the gitlink memory's index records,
  # and only memory's later `add -A` stages it. A transient index.lock between
  # the two leaves the tier ahead of its pin — the same shape the pin guard
  # refuses for a tier moved behind gitlore's back — and memory-commit-batch.sh
  # promises the next batch retries transparently. The retry must recognise its
  # own landed tier commit and finish, not abort with "no automatic remedy".
  half_landed_tier_fixture
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  # The fixture's shape, asserted rather than assumed: the tier commit landed
  # and memory's index still records the pin it started from.
  [ -f "$lock" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]

  rm -f "$lock"
  run --separate-stderr bash "$CMD" -F "$(gitlore_commit_msg_file memory)"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record the shared fact" ]
  git -C memory/ddaanet show HEAD:MEMORY.md > "$BATS_TEST_TMPDIR/carrier.md"
  assert_bullets "$BATS_TEST_TMPDIR/carrier.md" \
    '- [shared](shared.md) — fresh hook'
  [ -z "$(git -C memory status --porcelain)" ]
}

# The same retry under a project path holding a space: the landing record and
# the landed-tier staging both handle the tier's path, and the suite otherwise
# reaches a spaced root only when the ambient TMPDIR holds one.
@test "a half-landed tier commit retries to completion under a project path holding a space" {
  teardown_tmp_repo
  TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore test.XXXXXX")"
  export TMP_REPO
  cd "$TMP_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  half_landed_tier_fixture
  landing=$(gitlore_tier_landing_file memory/ddaanet)
  [[ "$landing" == *" "* ]]
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ -f "$lock" ]
  [ -f "$landing" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]

  rm -f "$lock"
  run --separate-stderr bash "$CMD" -F "$(gitlore_commit_msg_file memory)"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ ! -e "$landing" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a tier commit that never landed leaves no claim on a later foreign commit" {
  # The retry adopts a tier commit only because gitlore recorded, just before
  # making it, the pin it was made on. A tier commit that fails must drop that
  # record: otherwise a commit made later on the same pin by anyone else reads
  # as gitlore's own, and its gitlink is staged without composing up.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  hook="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/hooks/pre-commit"
  mkdir -p "$(dirname "$hook")"
  # shellcheck disable=SC2016  # $0 is the generated hook's own, not this shell's
  printf '#!/bin/sh\nrm -f "$0"\nexit 1\n' > "$hook"
  chmod +x "$hook"
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin_before" ]

  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"
  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  [[ "$stderr" == *"ahead of the pin"* ]]
}

@test "a commit that fails after composing keeps the approval for the retry" {
  # The pre-commit path retries on the summary file as it stands — only
  # commit-memory.sh rewrites it. The first run's compose re-texts the carrier,
  # a write newer than the summary, so a failure after it must restamp the file
  # or the retry is refused as unapproved for a projection the summary covers.
  half_landed_tier_fixture
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"
  # gitlore_commit_msg_freshness compares whole-second mtimes with `>=`, so a
  # carrier write landing in the summary's second would read fresh unrestamped.
  sleep 1

  write_sync_driver

  run --separate-stderr bash "$driver"
  [ "$status" -ne 0 ]
  # The fixture's shape: compose re-texted the carrier, and the run died past it.
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — fresh hook'
  [ -f "$lock" ]
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
}

# A composed carrier the run then fails to commit: the same one-shot hook
# refusal the foreign-commit case above uses, measured on the approval
# instead of on the landing record.
@test "a tier commit that fails after composing keeps the approval for the retry" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  hook="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/hooks/pre-commit"
  mkdir -p "$(dirname "$hook")"
  # shellcheck disable=SC2016  # $0 is the generated hook's own, not this shell's
  printf '#!/bin/sh\nrm -f "$0"\nexit 1\n' > "$hook"
  chmod +x "$hook"
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"
  # Whole-second mtimes compared with `>=` — see the case above.
  sleep 1
  pin_before=$(git -C memory rev-parse ":ddaanet")
  write_sync_driver

  run --separate-stderr bash "$driver"
  [ "$status" -ne 0 ]
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — fresh hook'
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin_before" ]
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
}

# The last step that can fail: memory's own commit, after the tier commit
# and `add -A` have landed.
@test "a memory commit that fails after composing keeps the approval for the retry" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  hook="$(git -C memory rev-parse --absolute-git-dir)/hooks/pre-commit"
  mkdir -p "$(dirname "$hook")"
  # shellcheck disable=SC2016  # $0 is the generated hook's own, not this shell's
  printf '#!/bin/sh\nrm -f "$0"\nexit 1\n' > "$hook"
  chmod +x "$hook"
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"
  sleep 1
  head_before=$(git -C memory rev-parse HEAD)
  write_sync_driver

  run --separate-stderr bash "$driver"
  [ "$status" -ne 0 ]
  # The fixture's shape: the tier commit landed and was staged, and memory's
  # commit is the step that failed.
  [ "$(git -C memory rev-parse ":ddaanet")" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ ! -e "$hook" ]
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
}

# A tier `live` advance refused as non-fast-forward without the two refs
# having diverged prepares no merge, so it restamps like any other failure.
# No fixture reaches that ancestry right after a commit — only a concurrent
# advance of `live` does — so the classifier is stood in for, over a `live`
# that really refuses the fast-forward.
@test "a tier live advance refused without divergence keeps the approval for the retry" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  git -C memory/ddaanet checkout -q --detach
  side=$(git -C memory/ddaanet commit-tree -p HEAD -m side "HEAD^{tree}")
  git -C memory/ddaanet branch -f live "$side"
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record the shared fact\n' > "$msgfile"
  sleep 1
  write_sync_driver "gitlore_classify_refusal() { printf 'unknown\\n'; }"

  run --separate-stderr bash "$driver"
  [ "$status" -ne 0 ]
  # The fixture's shape: the tier committed, and its `live` was not advanced.
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$(git -C memory rev-parse ":ddaanet")" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$side" ]
  [ ! -f "$(gitlore_merge_state_file memory/ddaanet)" ]
  [[ "$stderr" == *"tier 'ddaanet' — HEAD is not at its local 'live'"* ]]
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
}

# The landing record vouches for the commit made on its pin, never for one
# stacked on top of it: a retry whose tier HEAD's parent is not the recorded
# pin leaves the gitlink alone, and the pin guard names the tier ahead.
@test "a landing record does not adopt a foreign commit stacked on the landed one" {
  half_landed_tier_fixture
  pin_before=$(git -C memory rev-parse ":ddaanet")

  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$pin_before" ]
  rm -f "$lock"

  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"
  run --separate-stderr bash "$CMD" -F "$(gitlore_commit_msg_file memory)"
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  [[ "$stderr" == *"ahead of the pin"* ]]
}

# The driver the approval cases above share: gitlore_sync_memory_to_live
# called the way the pre-commit hook calls it, on the summary file as it
# stands. $1 = optional shell text run after the libraries are sourced, to
# stand a function in for a state no fixture reaches.
write_sync_driver() {
  driver="$BATS_TEST_TMPDIR/driver.sh"
  cat > "$driver" <<DRIVER
#!/usr/bin/env bash
set -euo pipefail
source "$PLUGIN_ROOT/scripts/lib/util.sh"
source "$PLUGIN_ROOT/scripts/lib/log.sh"
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"
${1:-}
gitlore_sync_memory_to_live memory
DRIVER
}

@test "a manifest refusal is reported and does not abort the commit" {
  # The other half of Item 1.2's amended rule, and slice 1's control: an
  # implementation that aborts on every gitlore_compose refusal passes slice 1
  # and fails this case, and one that aborts on neither does the reverse. The
  # tier stays ON its pin, so gitlore_compose_check_pins passes and the
  # manifest's dangling 'phantom' entry reaches gitlore_compose_check's rule 2
  # instead — the same induction "the rc-1 user arm does not tell a user to
  # retry a commit that succeeded" uses below, read here under CLAUDECODE=1 for
  # the agent arm.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet phantom
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"

  head_before=$(git -C memory rev-parse HEAD)
  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head_before" ]
  [[ "$stderr" == *"tier composition refused"* ]]
  [[ "$stderr" == *"the tier manifest lists 'phantom'"* ]]
  # The whole sentence after Item 1.2 slice 1 dropped its trailing clause about
  # a pin figure printed above — not the first half of a longer one.
  [[ "$stderr" == *"This commit also stages each tier at the commit its worktree is on now"* ]]
}

@test "a mid-merge tier is reported as a merge, not as a moved pin" {
  # A tier that is BOTH off its pin AND mid-merge must be reported by
  # gitlore_guard_stale_merge_state, not by the pin guard's own message. A
  # MERGE_HEAD with no merge-state file beside it classifies as
  # `orphaned-merge-head`, so the arm that fires is the one reporting a merge
  # gitlore did not prepare — not gitlore_emit_merge_directive, which is the
  # stale-with-merge-head arm. gitlore_compose_check_pins' own mid-merge line
  # offers `checkout --detach`, which would unlink MERGE_HEAD and destroy a
  # prepared merge. Slice 1's off-pin induction (an empty commit made directly inside
  # the tier worktree, never staged into memory's index) plus a MERGE_HEAD
  # written into the tier's gitdir, the shape
  # "a tier holding a merge gitlore did not prepare is not composed into"
  # above already uses. The existing mid-merge case's tier sits ON its pin, so
  # it cannot discriminate the pin guard's position against the per-tier
  # stale-merge loop's — this one can, because only a pin guard hoisted ahead
  # of that loop would see this tier before the loop reports it.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"

  # `--absolute-git-dir`, not a `$(cd … && pwd)` pair: CDPATH glues a directory
  # listing onto the front of such a capture.
  gd=$(git -C memory/ddaanet rev-parse --absolute-git-dir)
  git -C memory/ddaanet rev-parse HEAD > "$gd/MERGE_HEAD"

  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  # Three separate abort points answer this fixture — the per-tier stale-merge
  # loop, the pin guard, and gitlore_sync_tiers_to_live's own guard — so the
  # exit code alone cannot say which one fired, and only removing all three
  # reds it. The two stderr assertions are what discriminate the ordering.
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"holds a merge gitlore did not prepare"* ]]
  # Paired with "a tier moved off its pin aborts the commit" above, which
  # asserts this same phrase positively over the same induction minus the
  # MERGE_HEAD. That positive is what keeps this negative from going vacuous
  # if the pin header is ever reworded.
  [[ "$stderr" != *"moved off the commit the memory store records for it"* ]]
}

@test "a compose write failure aborts the commit" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  # Reuses the induction at tests/index_compose.bats:921: chmod a-w on the
  # carrier's directory fails the `mv` gitlore_compose_write makes into it (the
  # temp file itself lands in the tier's own gitdir, never here). A half-written
  # carrier must not be committed, so the approved summary must survive for the
  # retry rather than being consumed by an aborted commit.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"

  head_before=$(git -C memory rev-parse HEAD)
  chmod a-w memory/ddaanet
  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  chmod u+w memory/ddaanet
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ -f "$(gitlore_commit_msg_file memory)" ]
  # The exit code alone would pass against a silent abort, which is the worse
  # failure: a refused commit with nothing said about why. Header plus the
  # forwarded problem line, for the same two-faults reason as the rc-1 case.
  [[ "$stderr" == *"tier composition could not write an index"* ]]
  [[ "$stderr" == *"could not write memory/ddaanet/MEMORY.md"* ]]
  # The agent arm's remedy sentence. The header above proves the branch fired
  # and the problem line proves the forwarding, but neither pins what the agent
  # is told to do about it, and the two arms differ only here.
  [[ "$stderr" == *"Investigate that path (permissions, disk space, a read-only worktree)"* ]]
}

@test "an unrecognised compose status aborts and keeps the approval" {
  # gitlore_compose returns only 0, 1 or 2 (index-compose.sh:800-853), so the
  # `*)` arm is unreachable through the real function. Drive it directly with a
  # stub that redefines gitlore_compose after sourcing the real libs, in the
  # order gitlore_sync_memory_to_live's own header names (util, log, resolve).
  make_parent_with_memory
  printf -- '---\nname: local\ndescription: ""\n---\n\na local fact\n' > memory/local.md
  seed_root_bullet "local.md" "a local fact"
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: record a local fact\n' > "$msgfile"
  # gitlore_commit_msg_freshness compares whole-second mtimes with `>=`, so a
  # restamp landing in the same second as the summary would still read fresh
  # and this test's freshness assertion would go vacuous.
  sleep 1

  driver="$BATS_TEST_TMPDIR/driver.sh"
  cat > "$driver" <<DRIVER
#!/usr/bin/env bash
set -euo pipefail
source "$PLUGIN_ROOT/scripts/lib/util.sh"
source "$PLUGIN_ROOT/scripts/lib/log.sh"
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"
gitlore_compose() {
  printf 'stub: could not write memory/MEMORY.md\n'
  touch memory/MEMORY.md
  return 7
}
gitlore_sync_memory_to_live memory
DRIVER

  head_before=$(git -C memory rev-parse HEAD)
  run --separate-stderr bash "$driver"
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  # The whole arm text, not a bare "7": stderr carries tmpdir paths whose
  # mktemp suffix can contain the digit, so a substring match on it alone would
  # go vacuous without ever proving the `*)` arm was reached.
  [[ "$stderr" == *"unrecognised status (7)"* ]]
  # This is this test's half of the red: the restamp the fix adds is what keeps
  # the approval usable on the retry.
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
}

@test "the rc-1 user arm does not tell a user to retry a commit that succeeded" {
  # Item 1.2 makes an off-pin tier abort the commit, so that induction no
  # longer reaches this rc-1 manifest-refusal arm — re-homed onto a manifest
  # problem instead: 'phantom' is listed but never mounted, so
  # gitlore_compose_check refuses (rule 2) while the tier stays ON its pin, and
  # gitlore_compose_check_pins passes. A bats run inherits CLAUDECODE from the
  # invoking shell, and a subagent dispatch exports it as 1, so it is unset
  # explicitly below to read the USER arm regardless of the ambient environment.
  # Characterization: the wording is already correct, so no red exists here —
  # the two assertions are the same sentence's two endings, so no other
  # producer on this channel can satisfy or break them by accident.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet phantom
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"

  head_before=$(git -C memory rev-parse HEAD)
  # A bats run inherits CLAUDECODE from the invoking shell, and a subagent
  # dispatch exports it as 1, so it is unset explicitly here (as
  # tests/git_hook_memory_pre_commit.bats:29 also does) to read the user arm
  # regardless of the ambient environment.
  unset CLAUDECODE
  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" != "$head_before" ]
  [[ "$stderr" == *"ask it to repair the memory store."* ]]
  [[ "$stderr" != *"repair the memory store, then retry"* ]]
}

@test "the rc-2 user arm tells a user to retry" {
  # Slice 3's write-failure induction verbatim, CLAUDECODE unset. Own case
  # rather than an addition to the test above: the inductions are different
  # fixtures, and a bats body runs under errexit, so a second scenario
  # appended to the first would only ever run when the first already held.
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"

  head_before=$(git -C memory rev-parse HEAD)
  chmod a-w memory/ddaanet
  # A bats run inherits CLAUDECODE from the invoking shell, and a subagent
  # dispatch exports it as 1, so it is unset explicitly here (as
  # tests/git_hook_memory_pre_commit.bats:29 also does) to read the user arm
  # regardless of the ambient environment.
  unset CLAUDECODE
  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  chmod u+w memory/ddaanet
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [[ "$stderr" == *"ask it to repair the memory store, then retry."* ]]
}

@test "the pin-abort user arm tells a user to retry" {
  # The pin abort gets its own user-arm case, where a retry IS the right
  # instruction — unlike the rc-1 manifest refusal above, this commit never
  # went through. Slice 1's off-pin fixture verbatim, CLAUDECODE unset so this
  # reads the USER arm rather than the agent one.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"

  head_before=$(git -C memory rev-parse HEAD)
  # A bats run inherits CLAUDECODE from the invoking shell, and a subagent
  # dispatch exports it as 1, so it is unset explicitly here (as
  # tests/git_hook_memory_pre_commit.bats:29 also does) to read the user arm
  # regardless of the ambient environment.
  unset CLAUDECODE
  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  # The header fragment is what discriminates: the "…, then retry." ending is
  # shared verbatim with the rc-2 and `*)` user arms, so on its own it pins
  # nothing about *this* arm.
  [[ "$stderr" == *"moved off the commit the memory store records for it"* ]]
  [[ "$stderr" == *"ask it to repair the memory store, then retry."* ]]
  # Two things keep the negative below from going vacuous, both measured. An
  # empty or misrouted $stderr reds a positive above it rather than passing
  # here — dropping the arm's own `>&2` reds the header assertion. And the
  # string it refutes is the agent arm's own remedy sentence, asserted
  # positively by `a tier moved sideways off its pin aborts the commit`, so a
  # wording drift reds that test rather than leaving this one refuting wording
  # no producer still emits.
  [[ "$stderr" != *"Follow the remedy on each line above"* ]]
}
