#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/merge-memory

# A take fetches a tier before deciding what to adopt: a repair another
# consumer published, and a failed fetch or missing remote that must not
# suppress a local adoption already earned.

@test "a take fetches first and takes a repair another consumer published" {
  # A raw fetch (bypassing this repo's own take) can leave local 'live' ahead
  # of HEAD carrying a defect that another consumer has since fixed upstream.
  # The fetch has to run, and origin/live has to be read, before the local
  # adoption decides there is a local repair to make — otherwise this repo
  # repairs its own stale copy of the defect instead of taking the fix that
  # already reached the remote.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")
  # Premise: the raw fetch really leaves live ahead of HEAD, both at the arrival.
  git -C memory/ddaanet fetch -q origin live:live
  pin=$(git -C memory rev-parse ":ddaanet")
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]

  # Another consumer, working from the same arrival, fixes it and republishes.
  work="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-other-consumer.XXXXXX")"
  git clone -q "$TMP_REPO/.bare-ddaanet.git" "$work"
  (
    cd "$work" || exit 1
    git config user.email "test@example.com"
    git config user.name  "Test"
    git checkout -q -B live origin/live
    awk -v line='- [A](a.md) — x' \
      '!found && $0 == line { found = 1; next } { print }' MEMORY.md > MEMORY.md.new
    mv MEMORY.md.new MEMORY.md
    git commit -aqm "upstream fix"
    git push -q origin live
  )
  fixed_sha=$(git -C "$work" rev-parse HEAD)
  rm -rf "$work"
  # Premise: the fix is published, one commit on the arrival, one copy left.
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$fixed_sha" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-list --parents -n 1 "$fixed_sha")" = "$fixed_sha $remote_sha" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" show "$fixed_sha:MEMORY.md" | grep -cxF -- '- [A](a.md) — x')" -eq 1 ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"repaired"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$fixed_sha" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$(git -C memory/ddaanet rev-parse origin/live)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$fixed_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$fixed_sha" ]
}

@test "a failed fetch still adopts local live, reports the fetch failure, and the end compose records the adoption" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin live:live
  git -C memory/ddaanet checkout -q --detach live
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory rev-parse ":ddaanet")
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]

  strand_live_ahead_of_pin ddaanet
  live_sha=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$live_sha" != "$pin" ]

  url=$(git -C memory/ddaanet remote get-url origin)
  git -C memory/ddaanet remote set-url origin "$TMP_REPO/missing.git"

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"could not fetch tier 'ddaanet'"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  # A fetch that failed still reaches the end compose, so the tier adopted
  # from its local live is recorded now rather than left ahead of its pin,
  # where every pass and commit would refuse it until a later take. Fails
  # under a run that stops at the fetch failure.
  grep -q 'ddaanet/local.md' memory/MEMORY.md
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$live_sha" ]
  [ -z "$(git -C memory status --porcelain)" ]

  git -C memory/ddaanet remote set-url origin "$url"
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$live_sha" ]
}

@test "a tier with no remote still adopts local live, reports the missing remote, and the end compose records the adoption" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin live:live
  git -C memory/ddaanet checkout -q --detach live
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory rev-parse ":ddaanet")
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]

  strand_live_ahead_of_pin ddaanet
  live_sha=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$live_sha" != "$pin" ]

  git -C memory/ddaanet remote remove origin

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"tier 'ddaanet' has no remote configured"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  # Same as the failed fetch: the missing remote does not stop the run short
  # of the end compose, so the adoption is recorded.
  grep -q 'ddaanet/local.md' memory/MEMORY.md
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$live_sha" ]
}

@test "a dirty tier is refused before any fetch or adoption" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin live:live
  git -C memory/ddaanet checkout -q --detach live
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory rev-parse ":ddaanet")

  strand_live_ahead_of_pin ddaanet
  # A dirty tier refuses the whole take, ahead of the fetch that would fail.
  printf 'uncommitted\n' > memory/ddaanet/dirty.md
  git -C memory/ddaanet remote set-url origin "$TMP_REPO/missing.git"

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"tier 'ddaanet' has uncommitted changes, so nothing was taken"* ]]
  [[ "$output$stderr" != *"could not fetch"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
}

# A remote that never received `live` is nothing to take, not a failed fetch:
# git refuses the fetch of the missing ref, and the take reads that refusal as
# the expected miss, so a run that moved a tier still reaches its root write.

@test "a memory remote with no live yet is nothing to take, and the moved tier still reaches root" {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory — its remote has no 'live' branch yet; nothing to take"* ]]
  [[ "$output$stderr" != *"couldn't find remote ref"* ]]
  [[ "$output$stderr" != *"could not fetch"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  # The end-of-run root write: the move recorded, the index composed, the store clean.
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$remote_sha" ]
  grep -q 'ddaanet/upstream.md' memory/MEMORY.md
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a tier whose remote has no live yet is nothing to take, not a failed fetch" {
  wire_memory_remote
  bare=$(make_tier_remote ddaanet nolive)
  git -C memory -c protocol.file.allow=always submodule add --name ddaanet "$bare" ddaanet >/dev/null 2>&1
  git -C memory commit -q -m "Add ddaanet tier"
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier 'ddaanet' — its remote has no 'live' branch yet; nothing to take"* ]]
  [[ "$output$stderr" != *"could not fetch"* ]]
  [[ "$output" == *"memory — already holds everything its remote does"* ]]
}
