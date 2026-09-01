#!/usr/bin/env bats
# Merge-commit hygiene: explicit takes leave a clean memory store.
#
# Both parents of every gitlore merge already passed an approval gate — the
# local side at its own FR11 commit, the upstream side in the repo that
# published it — so a merge prompts for nothing and carries a canned message,
# and an explicit take commits its own bookkeeping instead of stranding it as
# working-tree dirt for the next FR11 episode to explain.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth

MERGE_CMD="$PLUGIN_ROOT/scripts/merge-memory.sh"
PUSH_CMD="$PLUGIN_ROOT/scripts/push-memory.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
}
teardown() { teardown_tmp_repo; }

wire_memory_remote() {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

# Publish a commit to the memory remote that this clone does not have.
push_memory_fact() {
  local work
  work="$(mktemp -d "$TMP_REPO/clone.XXXXXX")"
  (
    cd "$work" || exit 1
    git clone -q "$MEMORY_REMOTE" .
    git checkout -q live
    printf 'remote-only\n' > REMOTE.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -q -m "remote fact"
    git push -q origin live
  )
  rm -rf "$work"
}

mount_pinned_tier() {
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  # The state SessionStart leaves a tier in: a local `live` created from the
  # remote, worktree detached at it. Without one the push path skips the tier
  # entirely, so a suite that omits it never reaches the take.
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live
  # The store is detached at `live`, so a commit leaves `live` behind until
  # something advances it — every gitlore commit path does, and the push gate
  # refuses a store whose two refs disagree.
  git -C memory push -q . HEAD:live
}

# --- the canned-message helpers ---

@test "gitlore_store_repo_name strips the url down to the repo" {
  wire_memory_remote
  git -C memory remote set-url origin "git@example.com:org/ddaanet-memory.git"
  run gitlore_store_repo_name memory
  [ "$status" -eq 0 ]
  [ "$output" = "ddaanet-memory" ]
  git -C memory remote set-url origin "https://example.com/org/gitlore-memory"
  run gitlore_store_repo_name memory
  [ "$output" = "gitlore-memory" ]
}

@test "gitlore_store_repo_name falls back to the directory for a placeholder remote" {
  make_parent_with_memory
  git -C memory remote set-url origin "./.git/gitlore-placeholder"
  run gitlore_store_repo_name memory
  [ "$status" -eq 0 ]
  [ "$output" = "memory" ]
}

@test "gitlore_consumer_name is the parent repository's basename" {
  make_parent_with_memory
  run gitlore_consumer_name memory
  [ "$status" -eq 0 ]
  [ "$output" = "$(basename "$TMP_REPO")" ]
}

# --- explicit tier take: fast-forward + adoption commits its bookkeeping ---

@test "a tier take commits the root index and gitlink with the canned message" {
  wire_memory_remote
  mount_pinned_tier
  push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo' >/dev/null

  run bash "$MERGE_CMD"
  [ "$status" -eq 0 ]
  # The store is clean: the moved gitlink and recomposed index are committed.
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  # live followed the bookkeeping commit — the gitlink invariant holds.
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
  # Canned subject, taken tier subjects in the body.
  [ "$(git -C memory log -1 --format=%s)" = "Update MEMORY.md for ddaanet tier merge." ]
  git -C memory log -1 --format=%b | grep -qF "remote tier fact"
  # No FR11 prompt: nothing in the output asks for a summary or approval.
  [[ "$output" != *"approved summary"* ]]
}

@test "a tier take on a dirty memory store stays staged and rides the next commit" {
  # Pre-existing unapproved edits must never ride an unprompted commit: the
  # take degrades to the staged-pair discipline and says so.
  wire_memory_remote
  mount_pinned_tier
  gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — hook')
  printf 'unapproved\n' > memory/pending-fact.md

  run bash "$MERGE_CMD"
  [ "$status" -eq 0 ]
  # No commit: the gitlink memory records is still the old one …
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$gitlink" ]
  # … but the moved pair is STAGED, so the SessionStart pin cannot revert it.
  [ "$(git -C memory rev-parse :ddaanet)" = "$remote_sha" ]
  [[ "$output" == *"uncommitted changes"* ]]
  # The unapproved edit was not swept into anything. Last, because `run`
  # replaces $output and the assertion above reads the take's own report.
  run ! git -C memory cat-file -e "HEAD:pending-fact.md"
}

# --- divergence merges carry the canned message, unprompted ---

@test "a memory divergence merge commit is canned: subject names the repos, body lists the local side" {
  wire_memory_remote
  (
    cd memory || exit 1
    git checkout -q live
    printf 'local\n' > LOCAL.md
    git add -A
    git commit -q -m "local, unpublished"
    git checkout -q --detach live
  )
  push_memory_fact

  run --separate-stderr bash "$MERGE_CMD"
  [ "$status" -eq 1 ]
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]

  subject="$(git -C memory log -1 --format=%s)"
  [ "$subject" = "merge .memory-remote from $(basename "$TMP_REPO")" ]
  # Body: what the merge brought INTO live — the second-parent (local) side.
  # Everyone else reading the shared history already has the first-parent side.
  body="$(git -C memory log -1 --format=%b)"
  [[ "$body" == *"local, unpublished"* ]]
  [[ "$body" != *"remote fact"* ]]
}

@test "a tier divergence merge lands canned and leaves a committed root store" {
  wire_memory_remote
  mount_pinned_tier
  # Local tier commit …
  seed_tier_bullet ddaanet local-fact.md "local hook"
  ( cd memory/ddaanet && git add -A && GITLORE_MEMORY_COMMIT=1 git commit -q -m "local tier fact" )
  git -C memory/ddaanet push -q . HEAD:live
  commit_memory_state
  # … and an upstream one: diverged.
  push_tier_fact ddaanet '- [upstream](upstream.md) — upstream hook' >/dev/null

  run --separate-stderr bash "$MERGE_CMD"
  [ "$status" -eq 1 ]
  run --separate-stderr run_stub_synth memory/ddaanet
  [ "$status" -eq 0 ]

  subject="$(git -C memory/ddaanet log -1 --format=%s)"
  [ "$subject" = "merge .bare-ddaanet from $(basename "$TMP_REPO")" ]
  git -C memory/ddaanet log -1 --format=%b | grep -qF "local tier fact"
  # The root store committed the moved gitlink and recomposed index.
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory log -1 --format=%s)" = "Update MEMORY.md for ddaanet tier merge." ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
}

# --- push takes upstream ---

@test "push takes a behind memory store instead of deferring to /gitlore:merge" {
  wire_memory_remote
  push_memory_fact
  remote_sha=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)

  run --separate-stderr bash "$PUSH_CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse live)" = "$remote_sha" ]
  # Taken, not published: no commits credited to this run.
  [[ "$output$stderr" != *"published"*"commit(s)"* ]]
}

@test "push takes a behind tier, commits the bookkeeping, and publishes it" {
  wire_memory_remote
  mount_pinned_tier
  # Memory's own live is published so only the tier is behind.
  git -C memory push -q origin live
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — hook')

  run --separate-stderr bash "$PUSH_CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory log -1 --format=%s)" = "Update MEMORY.md for ddaanet tier merge." ]
  # The bookkeeping commit reached the memory remote in the same run.
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$(git -C memory rev-parse HEAD)" ]
}

@test "a take when memory and a tier are both behind stays fast-forward-only" {
  # Memory's ff arrives first and repins the tiers; the tier loop then finds
  # the tier current and manufactures no divergence out of two fast-forwards.
  wire_memory_remote
  mount_pinned_tier
  git -C memory push -q origin live
  tier_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — hook')
  # A second consumer took the tier and pushed the bookkeeping commit upstream.
  other="$(mktemp -d "$TMP_REPO/other.XXXXXX")"
  git clone -q "$MEMORY_REMOTE" "$other"
  (
    cd "$other" || exit 1
    git checkout -q live
    git -c protocol.file.allow=always submodule update --init --quiet ddaanet
    git -C ddaanet fetch -q origin live
    git -C ddaanet checkout -q --detach FETCH_HEAD
    git add ddaanet
    git -c user.email=t@t -c user.name=t commit -q -m "Update MEMORY.md for ddaanet tier merge."
    git push -q origin HEAD:live
  )
  rm -rf "$other"

  run --separate-stderr bash "$MERGE_CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" != *"merge prepared"* ]]
  # And the tier loop's catch-up records nothing twice: no failed empty commit.
  [[ "$msg" != *"bookkeeping commit failed"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_sha" ]
  [ -z "$(git -C memory status --porcelain)" ]
}
