#!/usr/bin/env bats
# A publication push refusal is worded by its own reason — a moved remote
# for a non-fast-forward, a plain failure for a policy decline — and a
# behind arm's repair on one tier survives a later tier's push failing.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/push-fixtures

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
  assert_aa_live_repairs "$aa_fact"

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
  assert_aa_live_repairs "$D"
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
  assert_aa_live_repairs "$D"
  [ "$(tr '\n' ' ' < "$ledger")" = "$P $aa_live " ]
  [ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse live)" = "$D" ]

  [[ "$output$stderr" == *"declined by policy"* ]]
  [[ "$output$stderr" == *"pushing tier 'aa' failed, and not because of divergence"* ]]
  [[ "$output$stderr" != *"The remote moved during the push"* ]]
  [[ "$output$stderr" != *"(non-fast-forward)"* ]]
  [[ "$output$stderr" != *"(fetch first)"* ]]
}
