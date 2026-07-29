#!/usr/bin/env bats
# Pins the push/fetch-rejection discriminator.
#
# Three sites route on git's parenthesized rejection reason to tell "the ref
# diverged, a merge can fix this" apart from "the server said no, a merge
# cannot":
#
#   scripts/lib/resolve.sh      push . HEAD:live        (head-vs-live)
#   scripts/git-hooks/pre-push  push origin live        (head-vs-remote)
#   scripts/cc-hooks/session-start.sh  fetch origin live:live  (tier ff-only)
#
# That text is git's UI, not a documented contract. If it drifts across a git
# version or a transport, a genuine divergence stops entering the resolve flow
# and gets reported as an unexpected failure instead — a silent misroute of the
# one path that exists to recover unpushed memory. These tests provoke each
# rejection against a real git and assert the text still matches, so the drift
# fails loudly here rather than in the field.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# Each @test is its own subshell, so a per-test export is consumed inside that
# same test — SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"

setup() { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

# The discriminator itself, mirrored from the three sites. Kept as one helper so
# every scenario below asserts the same expression the code evaluates; the
# "sites still use this" test guards the mirror against drifting from the code.
is_divergence() {
  case "$1" in
    *"(fetch first)"*|*"(non-fast-forward)"*) return 0 ;;
    *) return 1 ;;
  esac
}

# A bare remote seeded with a `live` branch, plus a working clone.
# Leaves: $BARE, and cwd = $WORK (a clone with live checked out).
seed_bare_and_clone() {
  BARE="$TMP_REPO/.char.git"
  WORK="$TMP_REPO/work"
  git init -q --bare -b main "$BARE"
  git clone -q "$BARE" "$WORK"
  cd "$WORK" || return 1
  git config user.email "test@example.com"
  git config user.name  "Test"
  echo seed > SEED.md
  git add SEED.md
  git commit -q -m "seed"
  git push -q origin HEAD:live
  git fetch -q origin
  git checkout -q -B live origin/live
}

# Advance the remote's `live` from a throwaway second clone, behind our back.
advance_remote_live() {
  local other
  other="$(mktemp -d "$TMP_REPO/other.XXXXXX")"
  git clone -q "$BARE" "$other"
  (
    cd "$other" || exit 1
    git checkout -q live
    echo remote-only > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "remote-only"
    git push -q origin live
  )
  rm -rf "$other"
}

@test "a stale-ref push rejection is classified as divergence" {
  seed_bare_and_clone
  advance_remote_live
  # Our origin/live is stale, so git cannot tell locally that this is non-ff:
  # the remote refuses and reports "(fetch first)".
  echo local-only > LOCAL.md
  git add LOCAL.md
  git commit -q -m "local-only"
  run --separate-stderr git push -q origin live
  [ "$status" -ne 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"(fetch first)"* ]]
  is_divergence "$msg"
}

@test "a known-diverged push rejection is classified as divergence" {
  seed_bare_and_clone
  advance_remote_live
  echo local-only > LOCAL.md
  git add LOCAL.md
  git commit -q -m "local-only"
  # With origin/live refreshed, git rejects locally and names the reason itself.
  git fetch -q origin
  run --separate-stderr git push -q origin live
  [ "$status" -ne 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"(non-fast-forward)"* ]]
  is_divergence "$msg"
}

@test "a local 'push . HEAD:live' rejection is classified as divergence" {
  # The resolve.sh site: no remote involved, HEAD detached off to one side of
  # the local `live`.
  seed_bare_and_clone
  echo on-live > ONLIVE.md
  git add ONLIVE.md
  git commit -q -m "on live"
  # Detach one commit back and build a sibling: `live` now holds a commit HEAD
  # does not contain, which is exactly the head-vs-live shape.
  git checkout -q --detach HEAD~
  echo on-head > ONHEAD.md
  git add ONHEAD.md
  git commit -q -m "on head"
  run --separate-stderr git push -q . HEAD:live
  [ "$status" -ne 0 ]
  msg="$output$stderr"
  is_divergence "$msg"
}

@test "an ff-only 'fetch origin live:live' rejection is classified as divergence" {
  # The session-start tier site: a refspec fetch into a branch ref refuses a
  # non-fast-forward without '+', which is the tier ff-only guarantee.
  seed_bare_and_clone
  advance_remote_live
  # Give our local `live` a commit the remote does not have, then try to ff it.
  echo local-only > LOCAL.md
  git add LOCAL.md
  git commit -q -m "local-only"
  git checkout -q --detach HEAD
  run --separate-stderr git fetch origin "live:live"
  [ "$status" -ne 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"(non-fast-forward)"* ]]
  is_divergence "$msg"
}

@test "a quiet fetch swallows the reason entirely (why the site drops -q)" {
  # The asymmetry that hid a real bug: `push -q` still reports why it was
  # rejected (every push scenario above passes with -q), but `fetch -q` prints
  # nothing at all and only exits 1. Any site that classifies a fetch rejection
  # must therefore run without -q, or the divergence arm is dead code.
  seed_bare_and_clone
  advance_remote_live
  echo local-only > LOCAL.md
  git add LOCAL.md
  git commit -q -m "local-only"
  git checkout -q --detach HEAD
  run --separate-stderr git fetch -q origin "live:live"
  [ "$status" -ne 0 ]
  [ -z "$output$stderr" ]
}

@test "a pre-receive decline is NOT classified as divergence" {
  # The case the discriminator exists for: the server refused on policy, the
  # ref is perfectly fast-forwardable, and a merge cannot help.
  seed_bare_and_clone
  cat > "$BARE/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "policy: live is protected" >&2
exit 1
HOOK
  chmod +x "$BARE/hooks/pre-receive"
  echo local-only > LOCAL.md
  git add LOCAL.md
  git commit -q -m "local-only"
  run --separate-stderr git push -q origin live
  [ "$status" -ne 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"pre-receive hook declined"* ]]
  run ! is_divergence "$msg"
}

@test "pre-push reports a policy rejection instead of preparing a merge" {
  # End-to-end routing, not just the string: a declined push must surface git's
  # own explanation and leave no half-prepared merge behind.
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  (
    cd memory || exit 1
    git checkout -q live
    echo new-fact > FACT.md
    git add FACT.md
    git commit -q -m "Add fact"
  )
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"

  cat > "$MEMORY_REMOTE/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "policy: live is protected" >&2
exit 1
HOOK
  chmod +x "$MEMORY_REMOTE/hooks/pre-receive"

  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  msg="$output$stderr"
  [[ "$msg" == *"not because of divergence"* ]]
  [[ "$msg" == *"policy: live is protected"* ]]
  # The merge flow must not have started: no prepared state, no pending pin.
  [[ "$msg" != *"memory merge prepared"* ]]
  run git -C memory rev-parse -q --verify refs/gitlore/pending
  [ "$status" -ne 0 ]
}

@test "resolve reports a policy rejection instead of preparing a merge" {
  # /gitlore:resolve is where the user lands after pre-push has correctly told
  # them the push failed for a reason other than divergence. Re-diagnosing it as
  # divergence here prepares a merge that cannot help — and sends them round the
  # same loop.
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live

  cat > "$MEMORY_REMOTE/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "policy: live is protected" >&2
exit 1
HOOK
  chmod +x "$MEMORY_REMOTE/hooks/pre-receive"
  # Something to push, so the gate reaches the remote rather than no-opping.
  (
    cd memory || exit 1
    echo new-fact > FACT.md
    git add FACT.md
    GITLORE_MEMORY_COMMIT=1 git commit -q -m "Add fact"
    git push -q . HEAD:live
  )

  run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh"
  [ "$status" -ne 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"not because of divergence"* ]]
  [[ "$msg" == *"policy: live is protected"* ]]
  [[ "$msg" != *"memory merge prepared"* ]]
  run git -C memory rev-parse -q --verify refs/gitlore/pending
  [ "$status" -ne 0 ]
}

@test "every discriminating site still keys on the pinned patterns" {
  # Guards the mirror above from drifting away from the code it stands in for:
  # if a site stops using this pattern pair, the scenarios go on passing while
  # testing nothing.
  #
  # pre-push is NOT in this list any more, and its absence is asserted below
  # rather than assumed: since D20 it discriminates nothing itself, it calls
  # gitlore_push_stores in scripts/lib/resolve.sh (already covered here) so the
  # standalone push entry point cannot diverge from the hook. Dropping a site
  # from this loop would otherwise be indistinguishable from losing its coverage.
  for site in \
    scripts/lib/resolve.sh \
    scripts/resolve.sh \
    scripts/cc-hooks/session-start.sh
  do
    run grep -c -e '"(fetch first)"\*|\*"(non-fast-forward)"' \
                -e '\*non-fast-forward\*|\*"fetch first"\*' \
                "$PLUGIN_ROOT/$site"
    [ "$status" -eq 0 ] || {
      echo "no pinned rejection pattern found in $site" >&2
      return 1
    }
  done

  # pre-push delegates instead of discriminating. If someone re-inlines the push
  # logic there, this fails and the site belongs back in the loop above.
  grep -qF 'gitlore_push_stores' "$PLUGIN_ROOT/scripts/git-hooks/pre-push"
  run grep -c '"(fetch first)"\*|\*"(non-fast-forward)"' \
      "$PLUGIN_ROOT/scripts/git-hooks/pre-push"
  [ "$status" -ne 0 ]
}
