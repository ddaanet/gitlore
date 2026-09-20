#!/usr/bin/env bats
# The merge continuation's own staging, adoption and message-build failure
# paths — split out of resolve_compose.bats.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# Each @test is its own subshell; a per-test `export GITLORE_GIT_RETRY_SCHEDULE`
# is consumed within that same test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/stub-synth
load helpers/resolve-compose

@test "a tier merge the root index cannot adopt lands, records nothing in the root, and is adopted by the next take" {
  # Staging the moved gitlink without the up projection puts the tier on its pin
  # while root still holds the older block, so the next compose writes that
  # older text over the merged carrier and reports success. The merge itself
  # still lands; the root records nothing, and the tier rests on its pin with
  # the merge in `live`, the shape the next take adopts.
  prepare_tier_merge_with_new_lines
  pin=$(git -C memory rev-parse :ddaanet)
  mem_before=$(git -C memory rev-parse HEAD)
  # A real gitlore_compose_check refusal: a line prefixed with an unmounted tier.
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"gone/x.md"* ]]
  # The merge landed and was published...
  merged=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-list --count --merges "$merged" -1)" = "1" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$merged" ]
  [ ! -f "$(git -C memory/ddaanet rev-parse --git-path gitlore-merge-state)" ]
  # ...the root recorded nothing: no gitlink staged, no bookkeeping commit...
  [ "$(git -C memory rev-parse :ddaanet)" = "$pin" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
  run ! grep -qF 'ddaanet/t.md' memory/MEMORY.md
  # ...and the tier is back on its pin, so no compose can project over it.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  # Editing MEMORY.md retriggers nothing that adopts a tier; the take does.
  [[ "$stderr" == *"/gitlore:merge"* ]]
  [[ "$stderr" != *"edit MEMORY.md"* ]]

  # The printed remedy: fix the store, take again.
  sed -i.bak '/gone\/x\.md/d' memory/MEMORY.md
  rm -f memory/MEMORY.md.bak
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/merge-memory.sh"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$merged" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$merged" ]
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
}

@test "an unadopted tier merge landed by /gitlore:merge also rests the tier on its pin" {
  # The `publish: no` exit is the continuation's second exit 0.
  prepare_tier_merge_with_new_lines "$PLUGIN_ROOT/scripts/merge-memory.sh"
  pin=$(git -C memory rev-parse :ddaanet)
  remote_before=$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"merged without publishing"* ]]
  [ "$(git -C memory rev-parse :ddaanet)" = "$pin" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$(git -C memory/ddaanet rev-list --count --merges live -1)" = "1" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$remote_before" ]
}

@test "an unadopted tier merge whose pin the merge does not contain stays on the merge and says so" {
  # Returning the tier to a pin that is not an ancestor of the merge would put
  # it on a commit the merge never built on. It stays put; the pin guard at the
  # next memory commit is what names the remedy, and this run says as much.
  prepare_tier_merge_with_new_lines
  sideways=$(git -C memory/ddaanet commit-tree -m sideways "$(git -C memory/ddaanet write-tree)")
  git -C memory update-index --cacheinfo "160000,$sideways,ddaanet"
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  merged=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$merged" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$sideways" ]
  [[ "$stderr" == *"stays on the merge"* ]]
}

@test "a staging failure in the continuation aborts before the commit, and a rerun lands the merge" {
  # A memory index.lock that outlasts gitlore_git's retries fails the root
  # index's staging after an adopted up projection. The continuation stops
  # there, before the merge commit, and keeps the merge state; it does not
  # read the failure as a tier the root could not adopt.
  prepare_tier_merge_with_new_lines
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  lock="$(git -C memory rev-parse --absolute-git-dir)/index.lock"
  : > "$lock"
  # Exported, not a prefix on `run`, and not empty: `${…:-default}` turns an
  # empty value into the default schedule of several seconds.
  export GITLORE_GIT_RETRY_SCHEDULE=0

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  rm -f "$lock"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"index.lock"* ]]
  [[ "$stderr" != *"could not take tier"* ]]
  # HEAD rather than MERGE_HEAD: "no merge commit" is a statement about HEAD,
  # and the abort comes before `commit`, so the tier still sits on the commit
  # the preparation left it on.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ -f "$(git -C memory/ddaanet rev-parse --git-path gitlore-merge-state)" ]

  # With the lock gone, rerunning the continuation lands and adopts the merge.
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
}

@test "a refused merge commit leaves no message file behind and keeps the merge for a rerun" {
  prepare_tier_merge_with_new_lines
  hook="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/hooks/commit-msg"
  printf '#!/bin/sh\necho "commit refused by hook" >&2\nexit 1\n' > "$hook"
  chmod +x "$hook"
  mkdir "$BATS_TEST_TMPDIR/msgtmp"
  export TMPDIR="$BATS_TEST_TMPDIR/msgtmp"

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"commit refused by hook"* ]]
  [[ "$stderr" == *"gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared."* ]]
  # Order, checked as one glob so a missing line fails on its own assertion
  # above: the gitlore line says what the refusal means, so it follows the
  # reason git and the hook already gave rather than preceding it.
  [[ "$stderr" == *"commit refused by hook"*"gitlore: the merge commit was refused"* ]]
  # The refused-commit arm, not the build arm: the message was built, so a run
  # that also claimed a build failure would be emitting both arms' text.
  [[ "$stderr" != *"the merge message could not be built"* ]]
  # Nor the message-file arm: the file was created, or the build would not run.
  [[ "$stderr" != *"the merge message file could not be created"* ]]
  [ -z "$(find "$TMPDIR" -name 'gitlore-merge-msg.*' -print -quit)" ]
  [ -f "$(git -C memory/ddaanet rev-parse --git-path gitlore-merge-state)" ]
  git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD >/dev/null
  # The synthesis the merger staged survives a refused commit, in both stores:
  # `commit` leaves the index alone when a hook declines it, so the rerun below
  # lands the same content rather than a recomposed approximation of it.
  [ -n "$(git -C memory/ddaanet diff --cached --name-only -- MEMORY.md)" ]
  [ -n "$(git -C memory diff --cached --name-only -- MEMORY.md)" ]

  rm -f "$hook"
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
}

@test "a message build failure leaves no message file behind and keeps the merge prepared" {
  prepare_tier_merge_with_new_lines
  mkdir "$BATS_TEST_TMPDIR/msgtmp"
  export TMPDIR="$BATS_TEST_TMPDIR/msgtmp"
  second=$(git -C memory/ddaanet rev-parse MERGE_HEAD)
  # Fail the message build, which lists the subjects the merge brings in from
  # its second parent. The stub is keyed on that revision range, so no other
  # git call in the run can match it, and every other invocation reaches the
  # real binary. The build is coupled to this argv by the stub alone: were it
  # to stop logging the range, nothing would fail the build and the status
  # assertion below would catch the run landing the merge instead.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_git=$(command -v git)
  log_hits="$BATS_TEST_TMPDIR/log-hits"
  : > "$log_hits"
  cat > "$fakebin/git" <<EOF
#!/bin/sh
case " \$* " in
  *" log --format=%s HEAD..$second "*) echo "\$*" >> "$log_hits"; exit 1 ;;
esac
exec "$real_git" "\$@"
EOF
  chmod +x "$fakebin/git"

  PATH="$fakebin:$PATH" run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  # The build is what failed, not some other call the stub forwarded.
  grep -qF -- "log --format=%s HEAD..$second" "$log_hits"
  # Already true of the unfixed script: the commit is never reached, so the
  # merge stays prepared — MERGE_HEAD, the merge state and the staged synthesis
  # all survive — and the scratch message file is removed on the way out.
  git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD >/dev/null
  [ -f "$(git -C memory/ddaanet rev-parse --git-path gitlore-merge-state)" ]
  [ -n "$(git -C memory/ddaanet diff --cached --name-only -- MEMORY.md)" ]
  [ -n "$(git -C memory diff --cached --name-only -- MEMORY.md)" ]
  [ -z "$(find "$TMPDIR" -name 'gitlore-merge-msg.*' -print -quit)" ]
  [[ "$stderr" == *"gitlore: the merge message could not be built, so the merge was not committed; the merge stays prepared."* ]]
  # The build arm, not the refused-commit arm, which the run never reaches.
  # No ordering glob pairs with it: the build's own failure is the stub's
  # silent `exit 1`, so there is no git reason on stderr for it to follow.
  [[ "$stderr" != *"the merge commit was refused"* ]]
  # Nor the message-file arm above it: the file was created, and the build
  # failed writing into it.
  [[ "$stderr" != *"the merge message file could not be created"* ]]

  # Prepared, not abandoned: with the stub gone the continuation lands.
  rm -f "$fakebin/git"
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
}

@test "a failed mktemp for the merge message file leaves the merge prepared" {
  prepare_tier_merge_with_new_lines
  mkdir "$BATS_TEST_TMPDIR/msgtmp"
  export TMPDIR="$BATS_TEST_TMPDIR/msgtmp"
  # A stub, not a missing TMPDIR: gitlore_git and the composition helpers take
  # mktemp under this same TMPDIR before the message file does, so pointing it
  # at a missing directory would kill the run elsewhere. The stub is keyed on
  # the merge-msg template, so only that call fails and every other mktemp
  # reaches the real binary.
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  real_mktemp=$(command -v mktemp)
  log_hits="$BATS_TEST_TMPDIR/mktemp-hits"
  : > "$log_hits"
  cat > "$fakebin/mktemp" <<EOF
#!/bin/sh
case " \$* " in
  *" ${TMPDIR}/gitlore-merge-msg.XXXXXX "*)
    echo "\$*" >> "$log_hits"
    echo "mktemp: failed to create file via template" >&2
    exit 1
    ;;
esac
exec "$real_mktemp" "\$@"
EOF
  chmod +x "$fakebin/mktemp"

  PATH="$fakebin:$PATH" run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  # The targeted call is the one that failed, not some other mktemp the stub
  # forwarded.
  grep -qF -- "${TMPDIR}/gitlore-merge-msg.XXXXXX" "$log_hits"
  # Already true of the unfixed script: the commit is never reached, so the
  # merge stays prepared — MERGE_HEAD, the merge state and the staged synthesis
  # all survive. No message file was ever created, so none may appear either.
  git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD >/dev/null
  [ -f "$(git -C memory/ddaanet rev-parse --git-path gitlore-merge-state)" ]
  [ -n "$(git -C memory/ddaanet diff --cached --name-only -- MEMORY.md)" ]
  [ -n "$(git -C memory diff --cached --name-only -- MEMORY.md)" ]
  [ -z "$(find "$TMPDIR" -name 'gitlore-merge-msg.*' -print -quit)" ]
  [[ "$stderr" == *"gitlore: the merge message file could not be created, so the merge was not committed; the merge stays prepared."* ]]
  # Order, checked as one glob so a missing line fails on its own assertion
  # above: the gitlore line follows mktemp's own reason rather than replacing
  # or preceding it.
  [[ "$stderr" == *"mktemp: failed to create file via template"*"gitlore: the merge message file could not be created"* ]]
  # Neither sibling arm: both sit below this one and the run never reaches them.
  [[ "$stderr" != *"the merge message could not be built"* ]]
  [[ "$stderr" != *"the merge commit was refused"* ]]

  # Prepared, not abandoned: with the stub gone the continuation lands.
  rm -f "$fakebin/mktemp"
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
}
