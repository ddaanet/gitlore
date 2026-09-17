#!/usr/bin/env bats
# Behind is not diverged.
#
# git refuses a push of a merely-BEHIND ref with the same "(non-fast-forward)"
# it gives a genuinely diverged one, so a site that classifies on that text
# alone sends a store with nothing to publish into the merge flow. The
# preparation finds nothing to merge and reports a merge it could not prepare —
# naming a worktree that is clean, which is why this went unread in the field.
#
# Ancestry is the discriminator these tests pin, plus the invariant the push
# path reasons from: a store is detached AT `live` (D17), so the push publishes
# `live` while the merge preparation reasons from HEAD. When those two name
# different commits, neither diagnosis describes what is wrong, and the failed
# preparation used to leave HEAD moved onto the authority — a diagnosis with a
# side effect, which is what left a store silently un-adopted.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

CMD="$PLUGIN_ROOT/scripts/push-memory.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
}
teardown() { teardown_tmp_repo; }

# A memory store wired to a bare remote and already published. Mirrors
# push_memory.bats's setup; the tier cases mount before publishing, so the
# remote wiring is separated from the fixture build.
wire_memory_remote() {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  publish_memory
}

publish_memory() {
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

# Advance the memory remote's `live` from a throwaway clone, behind our back:
# the local store is then strictly BEHIND, with nothing of its own to publish.
advance_memory_remote() {
  local other
  other="$(mktemp -d "$TMP_REPO/other.XXXXXX")"
  git clone -q "$MEMORY_REMOTE" "$other"
  (
    cd "$other" || exit 1
    git checkout -q live
    printf 'remote-only\n' > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "remote-only"
    git push -q origin live
  )
  rm -rf "$other"
}

add_memory_commit() {
  (
    cd memory || exit 1
    git checkout -q live
    printf 'new-fact\n' > "${1:-FACT.md}"
    git add -A
    git commit -q -m "${2:-Add fact}"
  )
}

# A tier in the state SessionStart leaves it in: local `live` created from the
# remote, worktree detached at `live`.
mount_tier_at_live() {
  local tier="${1:-ddaanet}"
  make_tier_in_memory "$tier"
  git -C "memory/$tier" fetch -q origin "live:live"
  git -C "memory/$tier" checkout -q --detach live
}

# --- the preparation must not move a ref when it prepares nothing ---

@test "a preparation with nothing to merge leaves the store's HEAD where it was" {
  wire_memory_remote
  advance_memory_remote
  git -C memory fetch -q origin live
  # HEAD is contained in origin/live, so there is no merge to make. The old
  # implementation detached onto the authority first and discovered that after.
  before=$(git -C memory rev-parse HEAD)
  run --separate-stderr gitlore_prepare_merge memory origin/live live
  [ "$status" -eq 1 ]
  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
}

@test "a preparation resolves pending from the given ref, not a HEAD an earlier interrupted run displaced" {
  # The edify incident: a prior gitlore_prepare_merge staged a real merge
  # (checkout --detach onto the authority, MERGE_HEAD set) and the caller died
  # before gitlore_write_merge_state ran. HEAD is now sitting ON the authority;
  # local `live` is untouched and still names the real divergent commit. A
  # retry that reads pending from HEAD would misdiagnose genuine divergence as
  # "authority already contains HEAD" and silently drop it.
  wire_memory_remote
  advance_memory_remote
  add_memory_commit LOCAL.md "local-only"
  git -C memory fetch -q origin live
  live_before=$(git -C memory rev-parse live)

  git -C memory update-ref refs/gitlore/pending "$(git -C memory rev-parse HEAD)"
  git -C memory checkout -q --detach origin/live

  run --separate-stderr gitlore_prepare_merge memory origin/live live
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse -q --verify MERGE_HEAD)" = "$live_before" ]
}

# --- remote flavor: behind, diverged, drift ---

@test "memory behind its remote is taken by fast-forward, not routed into a merge" {
  # A push is attempt → take → attempt again (D49), so being behind is resolved
  # here rather than handed back as an errand. What must not happen either way
  # is a merge preparation against a store with nothing to merge.
  wire_memory_remote
  advance_memory_remote
  remote_sha=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" != *"memory merge prepared"* ]]
  [[ "$msg" != *"could not prepare"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse live)" = "$remote_sha" ]
  run ! git -C memory rev-parse -q --verify refs/gitlore/pending
}

@test "a remote that moved on its own is not reported as commits this run published" {
  # origin/live advances during the push's own fetch, so the before/after
  # comparison the report is built on moves even though this run sent nothing.
  wire_memory_remote
  advance_memory_remote

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" != *"published 1 commit(s)"* ]]
}

@test "memory genuinely diverged from its remote still prepares a merge" {
  wire_memory_remote
  advance_memory_remote
  add_memory_commit LOCAL.md "local-only"

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  msg="$output$stderr"
  [[ "$msg" == *"memory merge prepared"* ]]
}

@test "a store whose HEAD is behind its own live is reported as drift, and no ref moves" {
  wire_memory_remote
  add_memory_commit LOCAL.md "local-only"
  # `live` ahead, HEAD pinned behind it: the field shape, where `push origin
  # live` is refused on a ref the merge preparation never looks at.
  git -C memory checkout -q --detach HEAD~
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  msg="$output$stderr"
  [[ "$msg" == *"is not at its local 'live'"* ]]
  [[ "$msg" == *"checkout --detach live"* ]]
  [[ "$msg" != *"memory merge prepared"* ]]
  [[ "$msg" != *"could not prepare"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
}

@test "a store whose HEAD is ahead of its own live has 'live' advanced, then publishes" {
  # The direction that would publish LESS than the store holds: `push origin
  # live` succeeds while the gitlink the parent records — HEAD — never reaches
  # the remote, which is the lockstep guarantee failing silently. It is also the
  # one direction that cannot mean anything else, so the preflight advances
  # `live` rather than sending the user off to run the one git command it would
  # have named.
  wire_memory_remote
  add_memory_commit LOCAL.md "local-only"
  git -C memory checkout -q --detach HEAD
  git -C memory branch -f live HEAD~
  head_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"stranded behind HEAD"* ]]
  [[ "$msg" != *"is not at its local 'live'"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$head_before" ]
  # The lockstep guarantee, met rather than reported: what the parent's gitlink
  # records is what the remote now holds.
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$head_before" ]
}

@test "a store stranded at its remote's commit publishes instead of failing again" {
  # The 0.5.0 field shape: a merge preparation that could not continue had
  # checked HEAD out at `origin/live` and left `live` where it was, so every
  # later push was refused on a ref no diagnosis looked at. Nothing here is this
  # repo's to publish — the run has to end clean anyway.
  wire_memory_remote
  advance_memory_remote
  git -C memory fetch -q origin live
  remote_sha=$(git -C memory rev-parse origin/live)
  git -C memory checkout -q --detach origin/live
  [ "$(git -C memory rev-parse live)" != "$remote_sha" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"stranded behind HEAD"* ]]
  [[ "$msg" != *"could not prepare"* ]]
  [[ "$msg" != *"is not at its local 'live'"* ]]
  [ "$(git -C memory rev-parse live)" = "$remote_sha" ]
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$remote_sha" ]
}

# --- tier loop: one behind tier is not a failed push ---

@test "a tier behind its remote is taken by the push, not left as an errand" {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  mount_tier_at_live ddaanet
  publish_memory
  remote_sha=$(push_tier_fact ddaanet "- [upstream](u.md) — hook")

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"ddaanet"* ]]
  [[ "$msg" != *"memory merge prepared"* ]]
  [[ "$msg" != *"could not prepare"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
}

# --- local flavor: the same misread against a store's own `live` ---

@test "memory HEAD behind its own live is reported as drift rather than an unpreparable merge" {
  make_parent_with_memory
  add_memory_commit LOCAL.md "local-only"
  git -C memory checkout -q --detach HEAD~
  head_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr gitlore_sync_memory_to_live memory
  [ "$status" -eq 1 ]
  msg="$output$stderr"
  [[ "$msg" == *"is not at its local 'live'"* ]]
  [[ "$msg" != *"could not prepare"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

# --- the tier direction a checkout cannot fix ---

@test "a tier whose local 'live' ran ahead of its pin is adopted by the push, not sent to a checkout" {
  # The 0.6.0 field shape: the preflight found HEAD at the recorded gitlink with
  # `live` ahead and prescribed `checkout --detach live`, which moves the tier
  # off its pin (D43) — the next composition then refuses, so obeying the push
  # gate put the store into the state the compose gate rejects. Adoption is what
  # the state actually calls for, and the push does it rather than naming it.
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  git -C memory push -q . HEAD:refs/heads/live
  publish_memory
  pin=$(git -C memory rev-parse ":ddaanet")

  strand_live_ahead_of_pin ddaanet
  live_sha=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  # The remedy that breaks the store is never named for a tier.
  [[ "$msg" != *"checkout --detach live"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$live_sha" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$live_sha" ]
  # And what was adopted was published: the tier's remote holds it.
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$live_sha" ]
}

@test "the head-vs-live gate sends a TIER to the take, not to a checkout that breaks its pin" {
  # Reached directly: with the preflight adopting first, the tier arm of the
  # gate fires only where a store's refs moved under an operation already in
  # flight. What it says there still has to be the remedy that does not strand
  # the store.
  make_parent_with_memory
  mount_tier_at_live ddaanet
  git -C memory/ddaanet checkout -q --detach live
  strand_live_ahead_of_pin ddaanet

  run --separate-stderr gitlore_check_head_live_agree memory/ddaanet "tier 'ddaanet'" ddaanet
  [ "$status" -eq 1 ]
  msg="$output$stderr"
  [[ "$msg" == *"is not at its local 'live'"* ]]
  [[ "$msg" == *"/gitlore:merge"* ]]
  [[ "$msg" != *"checkout --detach live"* ]]
  # And the possessive artifact the field report caught: a label already
  # carrying quotes must not be given an apostrophe-s on top of them.
  [[ "$msg" != *"''s"* ]]
}

# --- a repair the take makes inside a push publishes before memory records it ---

# The hook installed on $MEMORY_REMOTE runs inside memory's own receive-pack,
# which sets these to memory's quarantine; unset them before reading a wholly
# different repository's ref, or the git invocation below resolves against
# memory's object store instead of the tier's. Appended, one line per memory
# push: a later push must not overwrite an earlier one's snapshot.
install_tier_live_snapshot_hook() {
  local hookfile="$1"
  cat > "$MEMORY_REMOTE/hooks/pre-receive" <<HOOK
#!/bin/sh
unset GIT_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH
git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live >> "$hookfile"
exit 0
HOOK
  chmod +x "$MEMORY_REMOTE/hooks/pre-receive"
}

@test "a repair taken inside a push is published before memory records it" {
  # The take inside a push repairs a locally-stranded arrival before the loop
  # reaches memory's own push, and the tier push that follows it publishes the
  # repair — so the hook on memory's remote must see the repair already sitting
  # on the tier's remote when it fires.
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  git -C memory push -q . HEAD:refs/heads/live
  publish_memory
  pin=$(git -C memory rev-parse ":ddaanet")

  seed_tier_bullet ddaanet local.md "committed here, never recorded"
  strand_live_ahead_of_pin ddaanet
  stranded=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]

  hookfile="$BATS_TEST_TMPDIR/tier-live-at-memory-push"
  install_tier_live_snapshot_hook "$hookfile"

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ -s "$hookfile" ]
  R=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $stranded" ]
  [ "$(cat "$hookfile")" = "$R" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$R" ]
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live:ddaanet)" = "$R" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
  # The push is what publishes the repair, so it never sends the reader to run
  # /gitlore:push again.
  [[ "$output$stderr" == *"gitlore: tier 'ddaanet' — the repair is committed in its local 'live', and this push publishes it."* ]]
  [[ "$output$stderr" != *"/gitlore:push publishes it"* ]]
}

@test "a repair taken by the behind arm is published before memory records it" {
  # The behind arm's take can also repair the arrival, and the same holds for
  # it: the repair must reach the tier's remote before memory's own push
  # records the gitlink, not merely land locally while the loop moves on.
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  mount_tier_at_live ddaanet
  publish_memory
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")

  hookfile="$BATS_TEST_TMPDIR/tier-live-at-memory-push"
  install_tier_live_snapshot_hook "$hookfile"

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ -s "$hookfile" ]
  R=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(cat "$hookfile")" = "$R" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$R" ]
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live:ddaanet)" = "$R" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
  # The push is what publishes the repair, so it never sends the reader to run
  # /gitlore:push again.
  [[ "$output$stderr" == *"gitlore: tier 'ddaanet' — the repair is committed in its local 'live', and this push publishes it."* ]]
  [[ "$output$stderr" != *"/gitlore:push publishes it"* ]]
}

@test "a repair resting on a root problem inside a push publishes nothing until it is fixed" {
  # The take repairs the stranded arrival but root's own leftover line keeps it
  # from adopting: the repair waits in the tier's local `live`, and neither the
  # tier's remote nor memory's may learn of it. Once root is fixed, the next
  # push adopts that same repair and publishes it, tier before memory.
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"
  commit_memory_state
  git -C memory push -q . HEAD:refs/heads/live
  publish_memory
  pin=$(git -C memory rev-parse ":ddaanet")
  tier_remote_before=$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)
  memory_remote_before=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)

  seed_tier_bullet ddaanet local.md "committed here, never recorded"
  strand_live_ahead_of_pin ddaanet
  stranded=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"gone/x.md"* ]]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: dropped a duplicate pointer line:"* ]]
  [[ "$output$stderr" != *"publishes it"* ]]
  R=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $stranded" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$tier_remote_before" ]
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live)" = "$memory_remote_before" ]

  sed -i.bak '/gone\/x\.md/d' memory/MEMORY.md
  rm -f memory/MEMORY.md.bak
  commit_memory_state

  hookfile="$BATS_TEST_TMPDIR/tier-live-at-memory-push"
  install_tier_live_snapshot_hook "$hookfile"
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"repaired"* ]]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(cat "$hookfile")" = "$R" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$R" ]
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live:ddaanet)" = "$R" ]
}

# --- a repair the mid-loop take makes to a DIFFERENT tier is published too ---

# Advance a tier past its own remote with a plain commit that adds no index
# line — the ordinary shape of a local advance, before the push that would
# publish it. Leaves both HEAD and local `live` on the new commit (not
# stranded — `strand_live_ahead_of_pin` is the fixture for that shape).
# Args: $1 = tier, $2 = file (default "plain.md").
advance_tier_past_remote() {
  local tier="$1" file="${2:-plain.md}"
  printf 'x\n' > "memory/$tier/$file" || return 1
  git -C "memory/$tier" add "$file" || return 1
  GITLORE_MEMORY_COMMIT=1 git -C "memory/$tier" commit -q -m "plain commit, no index line" || return 1
  git -C "memory/$tier" branch -f live HEAD
}

# Build a commit as a child of $2, in a scratch clone of the tier's own local
# repo (so an ancestor never pushed to the tier's remote is still reachable),
# and push it to $3 on the tier's bare remote — a side ref, not `live`: the
# remote's `live` only moves once the hook below fires on its next receive.
# Echoes the new commit's sha. Args: $1 = tier, $2 = parent sha, $3 = ref,
# $4 = line appended to MEMORY.md.
push_side_ref_child() {
  local tier="$1" parent="$2" refname="$3" line="$4" work
  local bare="$TMP_REPO/.bare-$tier.git"
  work="$(mktemp -d "$BATS_TEST_TMPDIR/tier-work.XXXXXX")" || return 1
  git clone -q "memory/$tier" "$work" || return 1
  git -C "$work" config user.email "test@example.com" || return 1
  git -C "$work" config user.name "Test" || return 1
  git -C "$work" checkout -q --detach "$parent" || return 1
  printf '%s\n' "$line" >> "$work/MEMORY.md" || return 1
  git -C "$work" commit -aqm "duplicate arrival" || return 1
  git -C "$work" push -q "$bare" "HEAD:$refname" || return 1
  git -C "$work" rev-parse HEAD
}

# A one-shot post-receive hook on a tier's bare remote: on the next push it
# receives, it snaps `live` onto $2 and removes itself — the idiom
# half_landed_tier_fixture uses for a lock, here for a ref. Args: $1 = tier,
# $2 = the sha `live` lands on.
install_tier_live_snap_hook() {
  local tier="$1" target="$2"
  local hook="$TMP_REPO/.bare-$tier.git/hooks/post-receive"
  # shellcheck disable=SC2016  # $0 is the generated hook's own, not this shell's
  printf '#!/bin/sh\ngit update-ref refs/heads/live %s\nrm -f "$0"\n' "$target" > "$hook" || return 1
  chmod +x "$hook"
}

# Shared shape for both variants below: two tiers, `aa` mounted before `bb`
# (their `.gitmodules` order, which the tier loop and the take pass both
# read). `aa`'s own loop iteration publishes P; a post-receive hook then snaps
# its remote's `live` onto D — a child of P carrying a duplicate bullet twice
# (the arrival shape "a repair taken by the behind arm is published before
# memory records it" repairs) — behind the push's back. Whatever the
# variant does with `bb` next runs the take pass over every tier, `aa`
# included: it fast-forwards `aa` onto D and repairs the duplicate into a new
# commit entirely inside `aa`'s local `live` — `aa`'s own loop iteration
# already ran and does not come back around to publish it.
# Called directly, never in `$(...)`, so errexit covers every step. Sets $P, $D.
setup_repair_race_on_aa() {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  mount_tier_at_live aa
  mount_tier_at_live bb
  set_tier_manifest aa bb
  gitlore_compose memory
  commit_memory_state
  git -C memory push -q . HEAD:refs/heads/live
  publish_memory

  advance_tier_past_remote aa
  commit_memory_state
  git -C memory push -q . HEAD:refs/heads/live
  P=$(git -C memory/aa rev-parse HEAD)
  [ "$(git -C memory rev-parse live:aa)" = "$P" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse live)" != "$P" ]

  D=$(push_side_ref_child aa "$P" refs/heads/stash-d \
    "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")
  [ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse stash-d)" = "$D" ]
  install_tier_live_snap_hook aa "$D"
}

# Everything the defect rests on, asserted before the defect itself so a red
# can only mean the repair went unpublished: the push succeeded, the hook moved
# `aa`'s remote onto D, the take repaired `aa` on top of D, and memory's remote
# records that repair as `aa`'s gitlink. Args: $1 = the push's status, $2 = its
# combined output. Sets $aa_live.
assert_aa_repaired_mid_loop() {
  local push_status="$1" push_output="$2"
  [ "$push_status" -eq 0 ]
  [ ! -e "$TMP_REPO/.bare-aa.git/hooks/post-receive" ]
  git --git-dir="$TMP_REPO/.bare-aa.git" merge-base --is-ancestor "$D" live
  aa_live=$(git -C memory/aa rev-parse live)
  [ "$(git -C memory/aa rev-list --parents -n 1 "$aa_live")" = "$aa_live $D" ]
  [ "$(git -C memory/aa show "$aa_live:MEMORY.md" | grep -cF -- '- [A](a.md) — x')" -eq 1 ]
  [[ "$push_output" == *"repaired aa's arrival"* ]]
  [ "$(git --git-dir="$MEMORY_REMOTE" rev-parse live:aa)" = "$aa_live" ]
}

@test "a repair the take makes to another tier mid-loop is published, not left for the next push (behind)" {
  setup_repair_race_on_aa
  bb_fact=$(push_tier_fact bb "- [B](b.md) — y")

  run --separate-stderr bash "$CMD"
  assert_aa_repaired_mid_loop "$status" "$output$stderr"
  # `bb`'s behind arm is what ran the take: `bb` took its remote's fact.
  git -C memory/bb merge-base --is-ancestor "$bb_fact" live
  # The defect: `aa`'s own remote never received the repair memory records.
  run git --git-dir="$TMP_REPO/.bare-aa.git" cat-file -e "$aa_live^{commit}"
  [ "$status" -eq 0 ]
}

@test "a repair the take makes to another tier mid-loop is published, not left for the next push (ahead-of-HEAD)" {
  setup_repair_race_on_aa
  strand_live_ahead_of_pin bb
  bb_stranded=$(git -C memory/bb rev-parse live)

  run --separate-stderr bash "$CMD"
  assert_aa_repaired_mid_loop "$status" "$output$stderr"
  # `bb`'s ahead-of-HEAD arm is what ran the take: it adopted `bb`'s own
  # stranded commit and published it.
  [[ "$output$stderr" == *"tier 'bb' — its local 'live' held commits the memory store never recorded"* ]]
  git --git-dir="$TMP_REPO/.bare-bb.git" merge-base --is-ancestor "$bb_stranded" live
  run git --git-dir="$TMP_REPO/.bare-aa.git" cat-file -e "$aa_live^{commit}"
  [ "$status" -eq 0 ]
}

# --- a behind arm's own repair must survive a later tier's failure ---

# A pre-receive hook on tier $1's bare remote that declines every push for a
# reason other than divergence, after appending tier $2's remote `live` to file
# $3 — what $2 had published by the moment $1's push was tried, one line per
# attempt. The quarantine variables are unset for the reason
# install_tier_live_snapshot_hook gives. Args: $1 = declining tier,
# $2 = watched tier, $3 = snapshot file.
decline_tier_pushes_recording() {
  local tier="$1" watched="$2" snapfile="$3"
  local hook="$TMP_REPO/.bare-$tier.git/hooks/pre-receive"
  cat > "$hook" <<HOOK || return 1
#!/bin/sh
unset GIT_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH
git --git-dir="$TMP_REPO/.bare-$watched.git" rev-parse live >> "$snapfile"
echo "declined by policy" >&2
exit 1
HOOK
  chmod +x "$hook"
}

@test "a behind arm's repair survives a later tier's failure" {
  # aa is processed first (.gitmodules order) and its own behind arm repairs
  # the duplicate arrival by taking and correcting it, as in "a repair taken by
  # the behind arm is published before memory records it". bb comes next and
  # its remote declines every push, so the loop returns 1 there. aa's repair
  # has to be on aa's remote already when bb's push is tried.
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  mount_tier_at_live aa
  mount_tier_at_live bb
  publish_memory

  aa_fact=$(push_tier_fact aa "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")
  aa_live_before=$(git -C memory/aa rev-parse live)
  # aa is behind before the push: its own take is what repairs it.
  [ "$aa_live_before" != "$aa_fact" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse live)" = "$aa_fact" ]
  git --git-dir="$TMP_REPO/.bare-aa.git" merge-base --is-ancestor "$aa_live_before" "$aa_fact"

  advance_tier_past_remote bb
  snapfile="$BATS_TEST_TMPDIR/aa-remote-at-bb-push"
  decline_tier_pushes_recording bb aa "$snapfile"

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  # bb's refusal is the hook's policy decline, not a divergence.
  [[ "$output$stderr" == *"pushing tier 'bb' failed, and not because of divergence"* ]]
  [[ "$output$stderr" == *"declined by policy"* ]]
  [ -s "$snapfile" ]
  [[ "$output$stderr" == *"gitlore: tier 'aa' — the repair is committed in its local 'live', and this push publishes it."* ]]

  # aa's own take repaired it: the repair commit's parent is the fetched fact,
  # and its MEMORY.md carries the duplicate bullet once.
  aa_live=$(git -C memory/aa rev-parse live)
  [ "$aa_live" != "$aa_fact" ]
  [ "$(git -C memory/aa rev-list --parents -n 1 "$aa_live")" = "$aa_live $aa_fact" ]
  [ "$(git -C memory/aa show "$aa_live:MEMORY.md" | grep -cF -- '- [A](a.md) — x')" -eq 1 ]

  # aa's remote holds the repair, and held it already at bb's first push: the
  # behind arm publishes its own tier, not a pass that bb's failure skips or
  # that runs only after bb was tried.
  [ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse live)" = "$aa_live" ]
  [ "$(sed -n 1p "$snapfile")" = "$aa_live" ]
}

# --- the post-loop pass words a non-fast-forward refusal by its own reason ---

@test "a post-loop publication push refused as a non-fast-forward is worded as a moved remote, not as a non-divergence failure" {
  setup_repair_race_on_aa
  bb_fact=$(push_tier_fact bb "- [B](b.md) — y")

  # A `git` stub on PATH for the command under test only. It logs which tier
  # each `push -q origin live` names, and fails the second one naming `aa` as a
  # non-fast-forward; every other call goes to the real git. `aa`'s own
  # iteration pushes P before `bb`'s is reached, and neither `bb`'s behind arm
  # nor the take it runs sends `aa` to its remote, so an `aa` push logged after
  # `bb`'s can only be the post-loop pass publishing the take's repair.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_git=$(command -v git)
  pushes="$BATS_TEST_TMPDIR/tier-pushes"
  : > "$pushes"
  cat > "$fakebin/git" <<EOF
#!/bin/sh
case " \$* " in
  *"/aa push -q origin live ")
    echo aa >> "$pushes"
    if [ "\$(grep -c '^aa\$' "$pushes")" -eq 2 ]; then
      echo " ! [rejected]        live -> live (non-fast-forward)" >&2
      exit 1
    fi
    ;;
  *"/bb push -q origin live ") echo bb >> "$pushes" ;;
esac
exec "$real_git" "\$@"
EOF
  chmod +x "$fakebin/git"

  PATH="$fakebin:$PATH" run --separate-stderr bash "$CMD"

  # Everything the wording rests on, asserted first: the push failed; `aa`'s
  # push of P, `bb`'s refused push, then the pass's push of `aa` is the one
  # refused; `bb`'s take ran, repairing `aa` on top of D.
  [ "$status" -eq 1 ]
  [ "$(tr '\n' ' ' < "$pushes")" = "aa bb aa " ]
  git -C memory/bb merge-base --is-ancestor "$bb_fact" live
  aa_live=$(git -C memory/aa rev-parse live)
  [ "$(git -C memory/aa rev-list --parents -n 1 "$aa_live")" = "$aa_live $D" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse live)" = "$D" ]

  [[ "$output$stderr" == *"The remote moved during the push"* ]]
  [[ "$output$stderr" != *"not because of divergence"* ]]
}

# A pre-receive hook on tier $1's bare remote that accepts the first push it
# receives and declines by policy every one after, appending the sha each push
# offers for `live` to file $2 either way. A hook decline is not a divergence:
# git's own fast-forward check already passed, so its error carries no
# non-fast-forward reason. Args: $1 = tier, $2 = ledger file.
decline_tier_pushes_after_first() {
  local tier="$1" ledger="$2"
  local hook="$TMP_REPO/.bare-$tier.git/hooks/pre-receive"
  cat > "$hook" <<HOOK || return 1
#!/bin/sh
while read -r old new ref; do
  [ "\$ref" = refs/heads/live ] && echo "\$new" >> "$ledger"
done
if [ "\$(grep -c "" "$ledger")" -ge 2 ]; then
  echo "declined by policy" >&2
  exit 1
fi
exit 0
HOOK
  chmod +x "$hook"
}

@test "a post-loop publication push refused by policy is worded as a non-divergence failure, not as a moved remote" {
  setup_repair_race_on_aa
  bb_fact=$(push_tier_fact bb "- [B](b.md) — y")

  # No stub: real remotes. `aa`'s remote logs the commit each push offers. Its
  # own iteration offers P, accepted. The second push it receives is declined,
  # and it can only be the post-loop pass's if what it offers is the repair:
  # that commit does not exist until `bb`'s take makes it, and neither `bb`'s
  # behind arm nor the take sends `aa` to its remote.
  ledger="$BATS_TEST_TMPDIR/aa-pushed"
  : > "$ledger"
  decline_tier_pushes_after_first aa "$ledger"

  run --separate-stderr bash "$CMD"

  # Everything the wording rests on, asserted first: the push failed; `bb`
  # took its remote's fact, the take that repaired `aa` on top of D; `aa`'s
  # remote received P and then that repair, and declined the repair.
  [ "$status" -eq 1 ]
  git -C memory/bb merge-base --is-ancestor "$bb_fact" live
  aa_live=$(git -C memory/aa rev-parse live)
  [ "$(git -C memory/aa rev-list --parents -n 1 "$aa_live")" = "$aa_live $D" ]
  [ "$(tr '\n' ' ' < "$ledger")" = "$P $aa_live " ]
  [ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse live)" = "$D" ]

  [[ "$output$stderr" == *"declined by policy"* ]]
  [[ "$output$stderr" == *"pushing tier 'aa' failed, and not because of divergence"* ]]
  [[ "$output$stderr" != *"The remote moved during the push"* ]]
  [[ "$output$stderr" != *"(non-fast-forward)"* ]]
  [[ "$output$stderr" != *"(fetch first)"* ]]
}
