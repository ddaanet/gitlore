#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/commit-memory

# Compose refusals that are reported rather than aborted, and the rc-1/rc-2/
# pin-abort user-arm and agent-arm wording each of them carries.

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
  # Reuses the induction at tests/index_compose_dangling.bats: chmod a-w on the
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
  # gitlore_compose returns only 0, 1 or 2 (index-compose.sh:324-377), so the
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
