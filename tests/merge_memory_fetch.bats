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

@test "a failed fetch still adopts local live and reports the fetch failure" {
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

  git -C memory/ddaanet remote set-url origin "$TMP_REPO/missing.git"

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"could not fetch tier 'ddaanet'"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  grep -q 'ddaanet/local.md' memory/MEMORY.md
}

@test "a tier with no remote still adopts local live and reports the missing remote" {
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
  grep -q 'ddaanet/local.md' memory/MEMORY.md
}

@test "a failed adoption does not hide a failed fetch" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin live:live
  git -C memory/ddaanet checkout -q --detach live
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory rev-parse ":ddaanet")

  strand_live_ahead_of_pin ddaanet
  # A dirty tier refuses the adoption.
  printf 'uncommitted\n' > memory/ddaanet/dirty.md
  git -C memory/ddaanet remote set-url origin "$TMP_REPO/missing.git"

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"has uncommitted changes, so nothing was adopted"* ]]
  [[ "$output$stderr" == *"could not fetch tier 'ddaanet'"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
}
