#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# The spaced-root cases re-root $TMP_REPO inside their own test body.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth

CMD="$PLUGIN_ROOT/scripts/merge-memory.sh"
SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

# /gitlore:merge is the half of /gitlore:push that takes without publishing, and
# under pinned tiers it is the only path by which a tier advances at all. What is
# pinned here is that direction: what each store ends up holding, what reaches
# the root index, and that nothing of this repo's leaves it.
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

# Leave a store in the state a failed merge preparation produces: HEAD checked
# out at the commit `origin/live` names, and the local `live` — the ref a push
# sends and the only one a fast-forward advances — left where it was. From that
# moment the remote is contained in HEAD, so an ancestry test that reads HEAD
# alone calls the store finished while `live` stays behind.
strand_live_behind_head() {
  local store="$1"
  git -C "$store" fetch -q origin +refs/heads/live:refs/remotes/origin/live
  git -C "$store" checkout -q --detach origin/live
}

@test "exits 0 with a note when the repo has no gitlore-memory submodule" {
  run bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no gitlore-memory submodule"* ]]
}

@test "exits 0 in a session-less worktree where the memory worktree is absent" {
  wire_memory_remote
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT"
  run bash -c "cd '$WT' && bash '$CMD'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not checked out in this worktree"* ]]
  git worktree remove --force "$WT"
}

@test "rejects arguments" {
  run bash "$CMD" origin
  [ "$status" -eq 2 ]
}

@test "fast-forwards memory onto its remote and publishes nothing" {
  wire_memory_remote
  before=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  push_memory_fact
  remote_sha=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  run bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse live)" = "$remote_sha" ]
  [ -f memory/REMOTE.md ]
  # Detached, per the branch model.
  run git -C memory symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  # And the remote did not move: taking is not publishing.
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$remote_sha" ]
  [ "$before" != "$remote_sha" ]
}

@test "says so when a store already holds everything its remote does" {
  wire_memory_remote
  run bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already holds everything"* ]]
}

@test "advances a root store's local 'live' left stranded behind HEAD" {
  # The remote is contained in HEAD, so there is nothing to take — but `live`,
  # the ref the next push sends, is behind, and that push is refused again for
  # a reason neither ref explains. /gitlore:merge is the documented remedy, so
  # it is the thing that has to move `live`.
  wire_memory_remote
  behind=$(git -C memory rev-parse live)
  push_memory_fact
  remote_sha=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  strand_live_behind_head memory
  [ "$(git -C memory rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse live)" = "$behind" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse live)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse HEAD)" = "$remote_sha" ]
  [[ "$output$stderr" == *"stranded behind HEAD"* ]]
  # The repair is local: taking still publishes nothing.
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$remote_sha" ]
}

@test "advances a TIER's local 'live' left stranded behind HEAD" {
  # The shape the field incident had: the store the failed preparation moved was
  # a tier, and a tier is the store /gitlore:merge exists to advance.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  # The mount leaves the tier on `main` with no local `live`; the ref has to
  # exist, and be behind, for it to be strandable.
  git -C memory/ddaanet branch -f live origin/live
  behind=$(git -C memory/ddaanet rev-parse live)
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')
  strand_live_behind_head memory/ddaanet
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$behind" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [[ "$output$stderr" == *"tier 'ddaanet'"* ]]
  [[ "$output$stderr" == *"stranded behind HEAD"* ]]
}

@test "reports a store whose HEAD and 'live' have diverged instead of moving either" {
  # Only a `live` the current HEAD contains is unambiguously stranded. When each
  # ref holds a commit the other lacks, which one was intended is not
  # recoverable from the refs, so the repair declines and says so.
  wire_memory_remote
  base=$(git -C memory rev-parse HEAD)
  (
    cd memory || exit 1
    git checkout -q live
    printf 'on-live\n' > ON-LIVE.md
    git add -A
    GITLORE_MEMORY_COMMIT=1 git commit -q -m "on live only"
    git checkout -q --detach "$base"
    printf 'on-head\n' > ON-HEAD.md
    git add -A
    GITLORE_MEMORY_COMMIT=1 git commit -q -m "on HEAD only"
  )
  head=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
  [ "$(git -C memory rev-parse live)" = "$live" ]
  [[ "$output$stderr" == *"have each moved since they last agreed"* ]]
  # The repair runs before the no-op report, so a store that is about to fail is
  # never first told it holds everything it needs.
  [[ "$output$stderr" != *"already holds everything"* ]]
}

@test "leaves a store whose remote it is ahead of alone" {
  # Local commits awaiting publication are /gitlore:push's business. Taking
  # nothing is the right answer, and it must not read as a divergence.
  wire_memory_remote
  (
    cd memory || exit 1
    git checkout -q live
    printf 'local\n' > LOCAL.md
    git add -A
    git commit -q -m "local, unpublished"
    git checkout -q --detach live
  )
  head=$(git -C memory rev-parse HEAD)
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
  [[ "$output$stderr" != *"merge prepared"* ]]
}

@test "refuses a store with uncommitted changes instead of checking out over them" {
  wire_memory_remote
  push_memory_fact
  printf -- '- [dirty](dirty.md) — not committed yet\n' >> memory/MEMORY.md
  head=$(git -C memory rev-parse HEAD)
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"uncommitted changes"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
  grep -qF 'dirty.md' memory/MEMORY.md
}

@test "prepares a merge that will NOT publish when a store has diverged" {
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
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  # The mark the continuation reads: this merge reconciles, it does not share.
  statefile=$(gitlore_merge_state_file memory)
  [ "$(jq -r .publish "$statefile")" = "no" ]
}

@test "a merge aborted by hand is disposed of and re-prepared, not refused over" {
  # The observed producer of a state file without MERGE_HEAD: an agent asked to
  # revert to the pre-merge state runs a plain `git merge --abort` in the store,
  # which clears MERGE_HEAD and resets the index while gitlore's state file and
  # its three briefing artifacts stay put. Both this entry point and resolve.sh
  # used to refuse over what was left, with no path back.
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
  bash "$CMD" || true
  statefile=$(gitlore_merge_state_file memory)
  pending=$(jq -r .source_ref "$statefile")
  [ -n "$pending" ]

  git -C memory merge --abort
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD || true)" ]
  [ -f "$statefile" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [[ "$all" == *"nothing landed"* ]]
  [[ "$all" == *"leftover state is discarded"* ]]
  [[ "$all" == *"memory merge prepared"* ]]
  # The same merge, against the same divergent side, still marked reconcile-only.
  [ "$(jq -r .source_ref "$statefile")" = "$pending" ]
  [ "$(jq -r .publish "$statefile")" = "no" ]
}

@test "a push-prepared merge is not marked no-publish" {
  # The flag must not leak into the gates: a merge a refused push prepared
  # exists precisely so that push can go through.
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
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/push-memory.sh"
  [ "$status" -eq 1 ]
  statefile=$(gitlore_merge_state_file memory)
  [ "$(jq -r '.publish // ""' "$statefile")" = "" ]
}

@test "fails when a TIER has no remote configured" {
  # A tier exists to be shared, so one with no remote is a misconfiguration and
  # the whole reconcile stops on it.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet remote remove origin
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"no remote configured"* ]]
}

@test "memory with no remote is nothing to take, and the tiers still reconcile" {
  # The counterpart of the push side: a local-only memory store is a supported
  # end state, and its remote-lessness must not withhold the shared half.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')
  git -C memory remote remove origin
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to take"* ]]
  # The tier took what its own remote held.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
}

@test "a synced placeholder origin is nothing to take, not an unreachable remote" {
  wire_memory_remote
  # What `git submodule sync` leaves on a local-only install.
  git -C memory remote set-url origin "$TMP_REPO/.git/gitlore-placeholder"
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to take"* ]]
  [[ "$output$stderr" != *"could not fetch"* ]]
}

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

@test "a take repairs a duplicate pointer that arrived and adopts the repair" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")
  # Premise: the arrival really carries the duplicate on the tier's own remote,
  # and the check refuses it, so the check passing R below is the repair's doing.
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" show "$remote_sha:MEMORY.md" > "$BATS_TEST_TMPDIR/arrival.md"
  [ "$(grep -cxF -- '- [A](a.md) — x' "$BATS_TEST_TMPDIR/arrival.md")" -eq 2 ]
  [ -n "$(gitlore_compose_check_index "$BATS_TEST_TMPDIR/arrival.md")" ]
  gitdir_before=$(tier_gitdir_files ddaanet)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  # One parent, and it is the arrival: a commit on top, never a merge.
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(git -C memory/ddaanet log -1 --format=%s "$R")" = "Repair the MEMORY.md structure ddaanet received" ]
  [[ "$(git -C memory/ddaanet log -1 --format=%b "$R")" == *"dropped a duplicate pointer line: - [A](a.md) — x"* ]]
  git -C memory/ddaanet show "$R:MEMORY.md" > "$BATS_TEST_TMPDIR/repaired.md"
  [ -z "$(gitlore_compose_check_index "$BATS_TEST_TMPDIR/repaired.md")" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: dropped a duplicate pointer line: - [A](a.md) — x"* ]]
  [[ "$output$stderr" == *"/gitlore:push publishes it"* ]]
  # Adopted and recorded: memory commits the gitlink R with root's line once.
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
  [ "$(grep -cxF -- '- [A](ddaanet/a.md) — x' memory/MEMORY.md)" -eq 1 ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(tier_gitdir_files ddaanet)" = "$gitdir_before" ]
  # A take publishes nothing: the tier's remote still holds the arrival.
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$remote_sha" ]
}

@test "a take's repair keeps the duplicate its pin lacks" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  push_tier_fact ddaanet '- [A](a.md) — old' >/dev/null
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  [ "$(git -C memory/ddaanet show "$pin:MEMORY.md" | grep -cxF -- '- [A](a.md) — old')" -eq 1 ]
  # The arrival adds a second, differing line for the same path after the
  # pinned one, so a repair blind to the pin would keep the first, older line.
  remote_sha=$(push_tier_fact ddaanet '- [A](a.md) — new')

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  git -C memory/ddaanet show "$R:MEMORY.md" > "$BATS_TEST_TMPDIR/repaired.md"
  [ "$(grep -cxF -- '- [A](a.md) — new' "$BATS_TEST_TMPDIR/repaired.md")" -eq 1 ]
  ! grep -qF -- '— old' "$BATS_TEST_TMPDIR/repaired.md" || false
  [[ "$output$stderr" == *"dropped a duplicate pointer line: - [A](a.md) — old"* ]]
  [ "$(grep -cxF -- '- [A](ddaanet/a.md) — new' memory/MEMORY.md)" -eq 1 ]
  ! grep -qF -- 'ddaanet/a.md) — old' memory/MEMORY.md || false
}

# The files under a tier's gitdir outside what git itself keeps moving —
# objects, logs, refs, FETCH_HEAD, ORIG_HEAD — one per line, sorted. A take's
# scratch copy or temporary index left behind shows up as a difference.
tier_gitdir_files() {
  local gitdir
  gitdir=$(git -C "memory/$1" rev-parse --absolute-git-dir) || return 1
  (
    cd "$gitdir" || exit 1
    find . -type f ! -path './objects/*' ! -path './logs/*' ! -path './refs/*' \
      ! -name FETCH_HEAD ! -name ORIG_HEAD | LC_ALL=C sort
  )
}

@test "a take repairs a welded line that arrived" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_files ddaanet "$(printf -- '- [A](welded_a.md) — a- [B](welded_b.md) — b')" welded_b.md)
  # Premise: the arrival really carries the weld, unsplit.
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" show "$remote_sha:MEMORY.md" | grep -cxF -- '- [A](welded_a.md) — a- [B](welded_b.md) — b')" -eq 1 ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(git -C memory/ddaanet log -1 --format=%s "$R")" = "Repair the MEMORY.md structure ddaanet received" ]
  [[ "$(git -C memory/ddaanet log -1 --format=%b "$R")" == *"split a welded line before welded_b.md"* ]]
  [ "$(git -C memory/ddaanet show "$R:MEMORY.md" | tail -n 2)" = "$(printf -- '- [A](welded_a.md) — a\n- [B](welded_b.md) — b')" ]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: split a welded line before welded_b.md"* ]]
}

# push_tier_fact commits carrier lines alone; a weld's second path must also
# name a file in the tier for gitlore_repair_index to split it. Shaped like
# push_tier_fact: a plain clone commits the line plus each named file and pushes
# `live`. Args: $1 = tier, $2 = carrier line(s), then the files to create.
push_tier_files() {
  local tier="${1:-ddaanet}" line="$2"; shift 2
  local bare="$TMP_REPO/.bare-$tier.git" work
  work="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-tier-work.XXXXXX")"
  git clone -q "$bare" "$work"
  (
    cd "$work" || exit 1
    git config user.email "test@example.com"
    git config user.name  "Test"
    git checkout -q -B live origin/live
    printf '%s\n' "$line" >> MEMORY.md
    local f
    for f in "$@"; do
      printf 'body\n' > "$f"
    done
    git add -A
    git commit -qm "remote tier fact"
    git push -q origin live
  )
  git -C "$work" rev-parse HEAD
  rm -rf "$work"
}

@test "a take repairs an interleaved non-bullet line that arrived" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\nStray line here\n- [B](b.md) — y')")
  # Premise: the arrival really carries the stray line inside the bullet block.
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" show "$remote_sha:MEMORY.md" | tail -n 3)" = "$(printf -- '- [A](a.md) — x\nStray line here\n- [B](b.md) — y')" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(git -C memory/ddaanet log -1 --format=%s "$R")" = "Repair the MEMORY.md structure ddaanet received" ]
  [[ "$(git -C memory/ddaanet log -1 --format=%b "$R")" == *"moved a non-bullet line out of the pointer block: Stray line here"* ]]
  [ "$(git -C memory/ddaanet show "$R:MEMORY.md" | tail -n 3)" = "$(printf -- '- [A](a.md) — x\n- [B](b.md) — y\nStray line here')" ]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: moved a non-bullet line out of the pointer block: Stray line here"* ]]
}

@test "a repair beside a root problem lands in live and waits" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")
  memhead=$(git -C memory rev-parse HEAD)
  # Premise: root really carries the leftover prefix, committed.
  git -C memory show HEAD:MEMORY.md | grep -qF 'gone/x.md'

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [[ "$all" == *"gone/x.md"* ]]
  [[ "$all" == *"gitlore: repaired ddaanet's arrival: dropped a duplicate pointer line: - [A](a.md) — x"* ]]
  # What adoption waits on is the root problem alone: the first refusal's
  # carrier problem, already repaired, is not reported.
  run ! grep -qF 'duplicate pointer path' <<<"$all"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$gitlink" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  R=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(git -C memory rev-parse HEAD)" = "$memhead" ]

  sed -i.bak '/gone\/x\.md/d' memory/MEMORY.md
  rm -f memory/MEMORY.md.bak

  # The next take adopts R as it stands: no second repair commit.
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"repaired"* ]]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory/ddaanet rev-list --count "$remote_sha..live")" -eq 1 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$R" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
}

@test "an arrival the repair cannot fix walks back and names upstream" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [B](b.md) — y\n- [B](b.md) — y\n- [a](a.md) — a- [z](z.md) — z')")
  arrival_text=$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" show "$remote_sha:MEMORY.md")
  weld_line_n=$(printf '%s\n' "$arrival_text" | grep -nxF -- '- [a](a.md) — a- [z](z.md) — z' | cut -d: -f1)
  dup_line_n=$(printf '%s\n' "$arrival_text" | grep -nxF -- '- [B](b.md) — y' | head -n 1 | cut -d: -f1)
  # Premise: the identical duplicate sits above the weld, so dropping it moves
  # the weld up a line and the arrival's numbering differs from the repaired
  # copy's; and z.md names no file in the arrival, so the weld guard holds.
  [ -n "$weld_line_n" ]
  [ -n "$dup_line_n" ]
  [ "$dup_line_n" -lt "$weld_line_n" ]
  run ! git --git-dir="$TMP_REPO/.bare-ddaanet.git" cat-file -e "$remote_sha:z.md"
  gitdir_before=$(tier_gitdir_files ddaanet)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [[ "$all" == *"gitlore: tier 'ddaanet' took an index the take cannot repair; it is held in the tier's local 'live' and must be fixed where it was published:"* ]]
  [[ "$all" == *"live:MEMORY.md: line $weld_line_n welds"* ]]
  [[ "$all" != *"line $((weld_line_n - 1)) welds"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$gitlink" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]
  run ! grep -qxF 'Repair the MEMORY.md structure ddaanet received' < <(git -C memory/ddaanet log --all --reflog --format=%s)
  [ "$(tier_gitdir_files ddaanet)" = "$gitdir_before" ]
}

@test "a local live that ran ahead with a defective carrier is repaired" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin live:live
  git -C memory/ddaanet checkout -q --detach live
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory rev-parse ":ddaanet")
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]

  # The stranding helper seeds this bullet again, so its commit carries it twice.
  seed_tier_bullet ddaanet local.md "committed here, never recorded"
  strand_live_ahead_of_pin ddaanet
  stranded=$(git -C memory/ddaanet rev-parse live)
  # Premise: live really ran ahead of the pin, carrying the duplicate.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$stranded" != "$pin" ]
  [ "$(git -C memory/ddaanet show "$stranded:MEMORY.md" | grep -cxF -- '- [local](local.md) — committed here, never recorded')" -eq 2 ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  # Reached through the local adoption, not a remote fast-forward.
  [[ "$output$stderr" == *"held commits the memory store never recorded; adopted them at $(git -C memory/ddaanet rev-parse --short "$stranded")."* ]]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $stranded" ]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: dropped a duplicate pointer line: - [local](local.md) — committed here, never recorded"* ]]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
  [ "$(grep -cxF -- '- [local](ddaanet/local.md) — committed here, never recorded' memory/MEMORY.md)" -eq 1 ]
}

@test "a refused live update after the repair leaves no trace" {
  export GITLORE_GIT_RETRY_SCHEDULE=0
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin live:live
  git -C memory/ddaanet checkout -q --detach live
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory rev-parse ":ddaanet")
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]

  seed_tier_bullet ddaanet local.md "committed here, never recorded"
  strand_live_ahead_of_pin ddaanet
  stranded=$(git -C memory/ddaanet rev-parse live)
  [ "$stranded" != "$pin" ]
  [ "$(git -C memory/ddaanet show "$stranded:MEMORY.md" | grep -cxF -- '- [local](local.md) — committed here, never recorded')" -eq 2 ]

  # A submodule's gitdir lives under memory's own; resolve it, never assume.
  lock="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/refs/heads/live.lock"
  [ -f "$(git -C memory/ddaanet rev-parse --absolute-git-dir)/refs/heads/live" ]
  gitdir_before=$(tier_gitdir_files ddaanet)
  : > "$lock"

  run --separate-stderr bash "$CMD"
  rm -f "$lock"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  # The lock bit after the adoption checked `live` out, i.e. at R's push.
  [[ "$all" == *"held commits the memory store never recorded; adopted them at"* ]]
  [[ "$all" == *"live.lock"* ]]
  [[ "$all" != *"repaired ddaanet's arrival:"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$stranded" ]
  run ! grep -qxF 'Repair the MEMORY.md structure ddaanet received' < <(git -C memory/ddaanet log --all --reflog --format=%s)
  [ "$(tier_gitdir_files ddaanet)" = "$gitdir_before" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: dropped a duplicate pointer line: - [local](local.md) — committed here, never recorded"* ]]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $stranded" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
}

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
