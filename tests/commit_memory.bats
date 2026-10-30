#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# Each @test is its own subshell; a per-test `export GITLORE_GIT_RETRY_SCHEDULE`
# is read only by that test's own run.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/tier-fixtures
load helpers/commit-memory

# The basics, and the index-abort arm: a dirty root or tier index carrying a
# compose problem aborts the memory commit outright. What counts as a usable
# summary in the first place is in commit_memory_approval.bats.

@test "exits 0 when gitlore is not configured" {
  run --separate-stderr commit_sections "noop"
  [ "$status" -eq 0 ]
  # The caller is told nothing was committed, so it does not report a commit.
  [[ "$stderr" == *"nothing was committed: this repository has no memory submodule"* ]]
}

@test "exits 0 when memory is clean and synced" {
  make_parent_with_memory
  run commit_sections "memory: nothing to commit"
  [ "$status" -eq 0 ]
}

@test "exits 0 in a session-less worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  run commit_sections "noop"
  [ "$status" -eq 0 ]
}

@test "a summary on stdin commits dirty memory and advances live without a parent commit" {
  make_parent_with_memory
  parent_head_before=$(git rev-parse HEAD)
  echo dirty > memory/notes.md

  run commit_sections "memory: add notes"
  [ "$status" -eq 0 ]

  # Memory committed and live advanced.
  [ -z "$(git -C memory status --porcelain)" ]
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes" ]
  # No message file existed at any point.
  [ -z "$(claude_files)" ]
  # No parent commit happened.
  [ "$(git rev-parse HEAD)" = "$parent_head_before" ]
}

@test "gitlore-commit reads a sectioned summary from a heredoc" {
  make_parent_with_memory
  echo dirty > memory/notes.md

  run bash -c "'$PLUGIN_ROOT/bin/gitlore-commit' <<'EOF'
== memory ==
memory: from heredoc
EOF"
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: from heredoc" ]
}

@test "-m, -F and bare mode are gone: each is a usage error pointing at /gitlore:commit" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  head_before=$(git -C memory rev-parse HEAD)
  for args in "-m x" "-F -" "-x"; do
    # shellcheck disable=SC2086  # the option list is the point
    run --separate-stderr bash "$CMD" $args <<<"== memory ==
memory: add notes"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"usage: commit-memory.sh"* ]]
    [[ "$stderr" == *"/gitlore:commit"* ]]
  done
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ -n "$(git -C memory status --porcelain)" ]
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

  run commit_sections "memory: record the shared fact"
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

  CLAUDECODE=1 run --separate-stderr commit_sections "memory: record the shared fact"
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
  run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"aborted"* ]]
  [[ "${output}${stderr}" != *"the commit went ahead"* ]]
  [[ "${output}${stderr}" == *"Open this project in Claude Code"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head_before" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$tier_live_before" ]
}

@test "a dirty root index with a welded line aborts the memory commit" {
  # Root's own index carrying changes aborts like a dirty carrier does, here
  # on a rule 6 weld rather than a rule 1 duplicate.
  make_parent_with_memory
  printf -- '- [A](a.md) — a- [B](b.md) — b\n' >> memory/MEMORY.md
  n=$(wc -l < memory/MEMORY.md | tr -d ' ')

  head_before=$(git -C memory rev-parse HEAD)
  CLAUDECODE=1 run --separate-stderr commit_sections "memory: record a and b"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory/MEMORY.md: line $n welds two pointer bullets"* ]]
  # The weld line prints on the advisory arm too; these two name the arm.
  [[ "${output}${stderr}" == *"aborted"* ]]
  [[ "${output}${stderr}" != *"the commit went ahead"* ]]
  [ -n "$(git -C memory status --porcelain -- MEMORY.md)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "an interleaved non-bullet line in a dirty carrier aborts the memory commit" {
  # The duplicate-carrier fixture above, with a stray line between two distinct
  # bullets in place of the duplicate: a rule 4 problem aborts as rule 1 does.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet a.md "hook a"
  printf 'Stray line\n' >> memory/ddaanet/MEMORY.md
  seed_tier_bullet ddaanet b.md "hook b"
  seed_root_bullet "ddaanet/a.md" "hook a"
  seed_root_bullet "ddaanet/b.md" "hook b"

  CLAUDECODE=1 run --separate-stderr commit_sections "memory: record a and b"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: interleaved non-bullet line"* ]]
  [[ "${output}${stderr}" == *"aborted"* ]]
}

@test "an abort names every changed index file with a problem and no clean one" {
  # Three problem-bearing indexes: root and tier 'other' changed, tier
  # 'ddaanet' committed clean. The refusal lists all three problems; the abort
  # names the two files that would publish theirs.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  make_tier_in_memory other
  set_tier_manifest ddaanet other
  seed_tier_bullet ddaanet shared.md "hook"
  seed_tier_bullet ddaanet shared.md "hook"
  git -C memory/ddaanet add -A
  git -C memory/ddaanet commit -q -m "carrier: duplicate pointer"
  commit_memory_state
  [ -z "$(git -C memory/ddaanet status --porcelain -- MEMORY.md)" ]
  seed_tier_bullet other o.md "hook"
  seed_tier_bullet other o.md "hook"
  printf -- '- [A](a.md) — a- [B](b.md) — b\n' >> memory/MEMORY.md

  head_before=$(git -C memory rev-parse HEAD)
  CLAUDECODE=1 run --separate-stderr commit_sections "memory: record o"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory/ddaanet/MEMORY.md: duplicate pointer path shared.md"* ]]
  [[ "${output}${stderr}" == *"memory/other/MEMORY.md: duplicate pointer path o.md"* ]]
  [[ "${output}${stderr}" == *"memory/MEMORY.md: line "*" welds two pointer bullets"* ]]
  [[ "${output}${stderr}" == *"The changed index files with problems:
memory/MEMORY.md
memory/other/MEMORY.md
Fix them"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "a tier whose index status cannot be read aborts the commit and says which index" {
  # The rc-1 arm's fail-closed half. The pre-commit hook calls this behind
  # `|| exit $?`, which suspends errexit, so a status read that failed would
  # read as a clean index and let the commit publish the problem the refusal
  # just named. The read is stood in for rather than provoked: every way of
  # breaking a tier's gitdir also fails `git -C memory status` in
  # gitlore_memory_dirty, which exits 0 long before this arm.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "hook"
  seed_tier_bullet ddaanet shared.md "hook"
  seed_root_bullet "ddaanet/shared.md" "hook"

  head_before=$(git -C memory rev-parse HEAD)
  # shellcheck disable=SC2016  # stub text, expanded by the script copy that sources it
  stub_commit_script 'git() {
  if [ "$1" = -C ] && [ "$2" = memory/ddaanet ] && [ "$3" = status ]; then
    echo "fatal: simulated status failure" >&2
    return 128
  fi
  command git "$@"
}'
  CLAUDECODE=1 run --separate-stderr commit_sections "memory: record the shared fact"
  [ "$status" -eq 1 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  # Neither rc-1 arm answered: the read failed before either could be chosen.
  [[ "${output}${stderr}" != *"the commit went ahead"* ]]
  [[ "${output}${stderr}" != *"the commit was aborted because a problem is in an index file"* ]]
  [ -z "$(claude_files)" ]
  # A refused commit with nothing said about why is the worse failure: the caller
  # sees only a non-zero exit. What the abort owes is the index whose status
  # could not be read and that the commit stopped.
  [[ "$stderr" == *"could not read the status of memory/ddaanet/MEMORY.md"* ]]
  [[ "$stderr" == *"the commit was aborted"* ]]
  # The compose refusal that sent the run to this read travels with it: the
  # problem list is what the retry has to fix.
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md: duplicate pointer path shared.md"* ]]
}

@test "a root index whose status cannot be read aborts the commit and says which index" {
  # The same arm over root's own MEMORY.md, whose read decides the same
  # question. The stub matches the `-- MEMORY.md` pathspec form only, so the
  # bare `git -C memory status --porcelain` gitlore_memory_dirty makes earlier
  # in the run goes through and the abort reached is this one.
  make_parent_with_memory
  printf -- '---\nname: local\ndescription: ""\n---\n\nbody\n' > memory/local.md
  seed_root_bullet "local.md" "a local fact"
  seed_root_bullet "local.md" "a local fact"

  head_before=$(git -C memory rev-parse HEAD)
  # shellcheck disable=SC2016  # stub text, expanded by the script copy that sources it
  stub_commit_script 'git() {
  if [ "$1" = -C ] && [ "$2" = memory ] && [ "$3" = status ] && [ "${5:-}" = -- ]; then
    echo "fatal: simulated status failure" >&2
    return 128
  fi
  command git "$@"
}'
  CLAUDECODE=1 run --separate-stderr commit_sections "memory: record a local fact"
  [ "$status" -eq 1 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [[ "$stderr" == *"could not read the status of memory/MEMORY.md"* ]]
  [[ "$stderr" == *"the commit was aborted"* ]]
  [[ "$stderr" == *"memory/MEMORY.md: duplicate pointer path local.md"* ]]
  # Neither rc-1 arm answered: the read failed before either could be chosen.
  [[ "${output}${stderr}" != *"the commit went ahead"* ]]
  [[ "${output}${stderr}" != *"the commit was aborted because a problem is in an index file"* ]]
}


# A `git` first in PATH that fails the first `commit` it sees ($1 times) with an
# index.lock message, then runs the real git. Echoes the bin dir.
fake_git_lock_on_commit() {
  local bin="$BATS_TEST_TMPDIR/lockbin" real
  real=$(command -v git)
  mkdir -p "$bin"
  printf '0\n' > "$BATS_TEST_TMPDIR/commit-fails"
  cat > "$bin/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = commit ]; then
    n=\$(cat "$BATS_TEST_TMPDIR/commit-fails")
    if [ "\$n" -lt "$1" ]; then
      printf '%s\n' \$((n + 1)) > "$BATS_TEST_TMPDIR/commit-fails"
      echo "fatal: Unable to create '/r/.git/index.lock': File exists." >&2
      exit 128
    fi
    break
  fi
done
exec "$real" "\$@"
EOF
  chmod +x "$bin/git"
  printf '%s\n' "$bin"
}

@test "the root commit retries a transient index.lock" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  bin=$(fake_git_lock_on_commit 1)
  export GITLORE_GIT_RETRY_SCHEDULE=0

  PATH="$bin:$PATH" run commit_sections "memory: add notes under a lock"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/commit-fails")" = 1 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes under a lock" ]
}

@test "a tier commit retries a transient index.lock" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  echo dirty > memory/ddaanet/notes.md
  bin=$(fake_git_lock_on_commit 1)
  export GITLORE_GIT_RETRY_SCHEDULE=0

  PATH="$bin:$PATH" run commit_sections "memory: add a tier note under a lock"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/commit-fails")" = 1 ]
  [ "$(git -C memory/ddaanet log -1 --pretty=%s)" = "memory: add a tier note under a lock" ]
}
