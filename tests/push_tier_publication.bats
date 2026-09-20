#!/usr/bin/env bats
# The tier-loop take publishes a repair it makes to a stranded or drifted
# tier before memory records the gitlink, for both the tier it is repairing
# and one it repairs mid-loop while processing a different tier.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/push-fixtures

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

# --- the behind arm's own retry push words a refusal by its own reason ---

@test "a behind arm's retry push refused as a non-fast-forward is worded as a moved remote, not as a non-divergence failure" {
  # The arm's retry is the push that publishes what the take repaired, and it
  # is routed through the same reporter the rest of the loop uses — so a
  # refusal naming divergence is worded by what the tier's refs actually say:
  # `live` already contains the remote's, and the remote moved underneath.
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  mount_tier_at_live ddaanet
  publish_memory
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")

  # A `git` stub on PATH for the command under test only, the idiom the
  # post-loop cases below use. `ddaanet` is behind, so the real remote refuses
  # its first push and the behind arm takes and repairs the arrival; the retry
  # that publishes the repair is the second push naming the tier, and that is
  # the one the stub refuses as a non-fast-forward. Every other call goes to
  # the real git.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_git=$(command -v git)
  pushes="$BATS_TEST_TMPDIR/tier-pushes"
  : > "$pushes"
  cat > "$fakebin/git" <<EOF
#!/bin/sh
case " \$* " in
  *"/ddaanet push -q origin live ")
    echo ddaanet >> "$pushes"
    if [ "\$(grep -c '^ddaanet\$' "$pushes")" -eq 2 ]; then
      echo " ! [rejected]        live -> live (non-fast-forward)" >&2
      exit 1
    fi
    ;;
esac
exec "$real_git" "\$@"
EOF
  chmod +x "$fakebin/git"

  PATH="$fakebin:$PATH" run --separate-stderr bash "$CMD"

  # Everything the wording rests on, asserted first: the push failed; exactly
  # two pushes named the tier, so the refused one is the arm's own retry and
  # not the post-loop pass; and the take repaired the arrival on top of what
  # it fetched, which is what that retry was publishing.
  [ "$status" -eq 1 ]
  [ "$(tr '\n' ' ' < "$pushes")" = "ddaanet ddaanet " ]
  R=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]

  [[ "$output$stderr" == *"pushing tier 'ddaanet' was refused as a non-fast-forward"* ]]
  [[ "$output$stderr" == *"The remote moved during the push"* ]]
  [[ "$output$stderr" != *"not because of divergence"* ]]
  # A refused publication is not a divergence to resolve: nothing is prepared.
  [[ "$output$stderr" != *"memory merge prepared"* ]]
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
  assert_aa_live_repairs "$D"
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
  # `aa`'s own remote holds the repair memory records.
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

