#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
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

@test "a tier moved off its pin aborts the commit" {
  # gitlore_compose_check_pins refuses when a tier's worktree HEAD has moved off
  # the commit the memory store's INDEX records for it (D31, D36): projecting
  # root's text over an unadopted carrier would destroy approved upstream facts.
  # Item 1.2 makes that refusal abort the commit outright, rather than letting
  # the commit's own `add -A` stage the moved gitlink and erase the very
  # condition the refusal fired on. Reach the pin mismatch with an empty commit
  # made directly inside the tier worktree and never staged into memory's own
  # index: check_pins reads `:ddaanet`, and the check runs ahead of
  # gitlore_sync_tiers_to_live, so nothing has restaged that gitlink by the time
  # it looks. The carrier and the root line disagree as well, so the refusal has
  # real work to withhold rather than being a no-op.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  git -C memory/ddaanet commit -q --allow-empty -m "moved outside /gitlore:merge"

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
  # The approval survives the abort: gitlore_compose_check_pins writes nothing,
  # so the tree is no newer than the summary and the retry is not refused for a
  # change nobody made. It reads "absent" against unchanged code — the commit
  # lands and consumes the file — and "no" against an abort placed late enough
  # for the compose or the tier sync to have written first. What it cannot see
  # is a `touch "$msgfile"` in the abort arm: reaching here means the freshness
  # gate above already read yes, so a restamp changes no later answer, and the
  # runbook's "No restamp" is a rule about not copying a line whose reason does
  # not apply rather than a behaviour with an observable of its own.
  [ "$(gitlore_commit_msg_freshness memory)" = "yes" ]
  [[ "$stderr" == *"moved off the commit the memory store records for it"* ]]
  [[ "$stderr" == *"is checked out at"* ]]
  [[ "$stderr" == *"Return the tier to its pin with the command above"* ]]
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
  # gitlore_compose_check_pins passes. CLAUDECODE unset (the state a bats run
  # leaves it in anyway) so this reads the USER arm rather than the agent one.
  # Characterization: the wording is already correct, so no red exists here —
  # the two assertions are the same sentence's two endings, so no other
  # producer on this channel can satisfy or break them by accident.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet phantom
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"

  head_before=$(git -C memory rev-parse HEAD)
  # A bats run leaves CLAUDECODE unset, but the invoking shell may not — force
  # it, the way tests/git_hook_memory_pre_commit.bats:29 does, so this test
  # reads the user arm regardless of the ambient environment.
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
  # A bats run leaves CLAUDECODE unset, but the invoking shell may not — force
  # it, the way tests/git_hook_memory_pre_commit.bats:29 does, so this test
  # reads the user arm regardless of the ambient environment.
  unset CLAUDECODE
  run --separate-stderr bash "$CMD" -m "memory: record the shared fact"
  chmod u+w memory/ddaanet
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [[ "$stderr" == *"ask it to repair the memory store, then retry."* ]]
}
