#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# The spaced-root case re-roots $TMP_REPO inside its own test body.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory

# Pinned tiers: fast-forward and adoption into the root index, the
# stranded/diverged tier `live`, the staged-pair fallback, and a
# merge-prepared merge's continuation.

@test "fast-forwards a pinned tier and adopts its lines into the root index" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')

  run bash "$CMD"
  [ "$status" -eq 0 ]
  # The tier moved off its gitlink — the one operation that is allowed to do it.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$gitlink" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]
  # Adopted: the arrived line is in the always-loaded root index, prefixed.
  grep -qF -- '- [upstream](ddaanet/upstream.md) — published by another repo' memory/MEMORY.md
  # The moved gitlink and the recomposed index are one memory change, and an
  # explicit take records it under a canned message rather than leaving the
  # store dirty for the next FR11 episode to explain (D49).
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" != "$gitlink" ]
}

@test "a tier take the root index cannot adopt records nothing and is retaken once the store is fixed" {
  # Staging the gitlink without the up projection puts the tier back on its pin
  # while root still holds the older block, so the next compose writes that
  # older text over the carrier and reports success. A failed adoption therefore
  # leaves the tier where the store records it and keeps the arrival in `live`,
  # the shape the next take adopts.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')
  # A real gitlore_compose_check refusal: a line prefixed with an unmounted tier.
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"could not take tier 'ddaanet'"* ]]
  [[ "$stderr" == *"gone/x.md"* ]]
  # Nothing recorded: neither staged nor committed...
  [ "$(git -C memory rev-parse ":ddaanet")" = "$gitlink" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$gitlink" ]
  # ...the tier is back on that pin, so no compose can project over it...
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$gitlink" ]
  # ...and the arrival is kept where the next take looks for it.
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]
  run ! grep -qF 'ddaanet/upstream.md' memory/MEMORY.md

  # The printed remedy: fix the store, take again.
  sed -i.bak '/gone\/x\.md/d' memory/MEMORY.md
  rm -f memory/MEMORY.md.bak
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$remote_sha" ]
  grep -qF -- '- [upstream](ddaanet/upstream.md) — published by another repo' memory/MEMORY.md
}

# A take whose pair cannot be staged prints the staging command for a human
# to run. Under a project path holding a space it must still run verbatim,
# from anywhere: quoted, and absolute rather than relative to the project
# root the take ran from. A `git` shim refuses only the pair's `add`, so the
# fetch, the fast-forward and the up projection all land first.
@test "a take whose pair cannot be staged prints a staging command that runs from anywhere under a spaced root" {
  teardown_tmp_repo
  TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore test.XXXXXX")"
  export TMP_REPO
  cd "$TMP_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_git=$(command -v git)
  cat > "$fakebin/git" <<EOF
#!/bin/sh
case " \$* " in
  *" add -- MEMORY.md "*) echo "fatal: shim refuses the pair" >&2; exit 128 ;;
esac
exec "$real_git" "\$@"
EOF
  chmod +x "$fakebin/git"

  PATH="$fakebin:$PATH" run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  # The fixture's shape: the tier advanced and the pair is not staged.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse ":ddaanet")" != "$remote_sha" ]
  line=$(printf '%s\n' "$stderr" | grep -F 'could not be staged')
  cmd=${line#*\`}
  cmd=${cmd%%\`*}
  [[ "$cmd" == *"gitlore test."* ]]
  (cd / && eval "$cmd")
  [ "$(git -C memory rev-parse ":ddaanet")" = "$remote_sha" ]
  [ -n "$(git -C memory diff --cached --name-only -- MEMORY.md)" ]
}

@test "a fast-forwarded tier survives the next SessionStart's unconditional pin" {
  # The window the staged-pair discipline exists for, on the one path that still
  # reaches it: the root store held unapproved work before the take, so the pair
  # was staged rather than committed, and the tier pass re-pins every tier
  # unconditionally and by design.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')
  printf 'unapproved\n' > memory/pending-fact.md

  bash "$CMD"
  # The fixture must give the pin somewhere destructive to go: the tier is off
  # the commit memory records, and memory has not committed the move.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [ "$remote_sha" != "$gitlink" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$gitlink" ]

  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]

  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  # The adopted line and the fact it routes to are still in agreement — the
  # revert took the carrier back while leaving the composed root index in place,
  # which is worse than losing both.
  grep -qF -- '- [upstream](ddaanet/upstream.md) — published by another repo' memory/MEMORY.md
  grep -qF -- '- [upstream](upstream.md) — published by another repo' memory/ddaanet/MEMORY.md
}

@test "landing a merge-prepared merge advances local live but publishes nothing" {
  # The end of the no-publish path: the continuation reads the mark and stops
  # after the local fast-forward, which is the whole difference from a push.
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
  remote_before=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]

  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"merged without publishing"* ]]
  # The merge landed locally: HEAD is the merge commit and live followed it.
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
  [ -f memory/LOCAL.md ]
  [ -f memory/REMOTE.md ]
  # And the remote is exactly where it was.
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$remote_before" ]
}

@test "a tier fast-forward publishes nothing of this repo's" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  mem_remote_before=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo' >/dev/null
  tier_remote_before=$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)

  run bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$mem_remote_before" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$tier_remote_before" ]
}

@test "adopts a TIER's local 'live' that ran ahead of the commit the memory store records" {
  # The other half of the stranded-ref pair, and the one a checkout cannot fix:
  # `live` holds approved tier commits, HEAD sits at the pin, and moving HEAD
  # onto `live` alone takes the tier off the commit the store records (D43), so
  # the next composition refuses. Adoption is the only resolution that leaves
  # both the pin and the root index describing what the carrier holds.
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

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  # HEAD adopted what `live` held...
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  # ...the memory store records where the tier now sits...
  [ "$(git -C memory rev-parse ":ddaanet")" = "$live_sha" ]
  # ...and the carrier's line reached the always-loaded root index.
  grep -q 'ddaanet/local.md' memory/MEMORY.md
  # Which is composition's own test: the pin and the checkout name one commit.
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  # Recorded, not merely staged (D49): an explicit take leaves a clean store, and
  # a staged pair is the degraded path a dirty root falls back to.
  [ "$(git -C memory rev-parse "HEAD:ddaanet")" = "$live_sha" ]
  [ -z "$(git -C memory status --porcelain)" ]
  # Taking still publishes nothing.
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" != "$live_sha" ]
}

