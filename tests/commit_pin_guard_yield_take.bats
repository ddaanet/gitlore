#!/usr/bin/env bats
# The commit path's pin guard (rule 7) yields wherever /gitlore:merge would
# refuse the take for uncommitted changes: in the memory root, or in any mounted
# tier that holds them and has something to take. A tier off its pin whose
# remedy is /gitlore:merge is then left unrecorded, the commit goes through and
# names /gitlore:merge, and the merge that follows converges. The state of the
# world that makes the take refuse is read through one fetch per tier per
# process. tests/commit_pin_guard_yield.bats holds the root-refused cases (root
# dirty and forked from `live`); this file holds the cases where the refused
# store is another tier, or the off-pin tier itself.
#
# Tier ddaanet ("A") is off its pin; tier org ("B") sits on its pin. "red" tests
# fail against code that yields only for a root refusal; "lock-in" tests pass
# before and after, and pin refusals that stay.
bats_require_minimum_version 1.5.0
load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order

# The fixture root moves to a path with a space; called first in a test.
spaced_repo() {
  local outer="$BATS_TEST_TMPDIR/outer dir"
  mkdir -p "$outer"
  rm -rf "$TMP_REPO"
  TMP_REPO="$outer/proj dir"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
  mkdir "$TMP_REPO"
  cd "$TMP_REPO" || return 1
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name "Test"
}

fork_live_locally() {
  git -C memory branch -f live "$(git -C memory commit-tree "HEAD^{tree}" -p HEAD~1 -m elsewhere)"
  [ "$(git -C memory merge-base HEAD live)" != "$(git -C memory rev-parse live)" ]
}

dirty_root() {
  printf -- '---\nname: dirty\ndescription: ""\n---\n\nbody\n' > memory/dirty.md
  seed_root_bullet dirty.md "an uncommitted root fact"
}

# --- tier A's relation to its pin, with tier B mounted on its pin ---------------

a_behind() {
  take_base_store ddaanet org
  local_tier_commit_recorded ddaanet loc.md
  git -C memory/ddaanet checkout -q --detach HEAD~1
}

a_ahead() {
  take_base_store ddaanet org
  local_tier_commit_recorded ddaanet loc.md
  move_tier_off_pin_into_live ddaanet
}

# Ahead of its pin, and its remote gained a commit HEAD lacks.
a_ahead_upstream() {
  a_ahead
  push_tier_fact ddaanet "- [up2](up2.md) — from upstream" >/dev/null
}

# Behind its pin, then a commit of its own beside the pin: forked from `live`.
a_forked() {
  a_behind
  seed_tier_bullet ddaanet hand.md "hand fact"
  git -C memory/ddaanet add -A
  git -C memory/ddaanet commit -qm hand
}

# Root records a commit of A this checkout lacks, which A's remote holds.
a_unheld() {
  local work
  take_base_store ddaanet org
  local_tier_commit_recorded ddaanet loc.md
  git -C memory/ddaanet push -q origin HEAD:refs/heads/live
  work="$(mktemp -d "$TMP_REPO/twork.XXXXXX")"
  git clone -q -b live "$TMP_REPO/.bare-ddaanet.git" "$work"
  (
    cd "$work" || exit 1
    git config user.email "test@example.com"
    git config user.name "Test"
    printf -- '- [up](up.md) — published upstream\n' >> MEMORY.md
    printf -- '---\nname: up\ndescription: ""\n---\n\nbody\n' > up.md
    git add -A
    git commit -qm "upstream tier fact"
    git push -q origin live
  )
  local up
  up=$(git -C "$work" rev-parse HEAD)
  rm -rf "$work"
  git -C memory update-index --cacheinfo "160000,$up,ddaanet"
  seed_root_bullet ddaanet/up.md "published upstream"
  git -C memory add MEMORY.md
  git -C memory commit -qm "another checkout recorded ddaanet"
  git -C memory push -q . HEAD:refs/heads/live
}

# --- tier B's dirt ----------------------------------------------------------------

# B's remote gains a commit its HEAD lacks, so B has something to take.
b_arrivals() { push_tier_fact org "- [up](up.md) — from upstream" >/dev/null; }

# An uncommitted fact in B, with its carrier line.
b_carrier_edit() { seed_tier_bullet org new.md "an uncommitted org fact"; }
b_untracked() { printf -- '---\nname: new\ndescription: ""\n---\n\nbody\n' > memory/org/new.md; }
b_staged() { b_untracked; git -C memory/org add new.md; }

# An uncommitted carrier edit in A.
a_carrier_edit() { seed_tier_bullet ddaanet new.md "an uncommitted tier fact"; }

# --- driving and asserting ------------------------------------------------------

# One memory commit, then the compose the commit asks for and a second commit.
commit_following_compose() {
  run commit_sections "memory: record"
  if [[ "$output" == *"Run gitlore-compose"* ]]; then
    run bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
    run commit_sections "memory: record"
  fi
}

# The commit yielded A: it went through, A's gitlink is neither moved nor
# staged, /gitlore:merge is named, and no refusal was printed. $1 = A's pin.
assert_a_yielded() {
  local pin="$1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier 'ddaanet' is checked out off the commit the memory store records for it, so this commit recorded root's own changes and left the tier unrecorded. Run /gitlore:merge next"* ]]
  [[ "$output" != *"a tier was moved off the commit the memory store records"* ]]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin" ]
  [ -z "$(git -C memory diff --cached --name-only -- ddaanet)" ]
}

# B's work was committed in B and recorded by this commit.
assert_b_committed() {
  git -C memory/org cat-file -e HEAD:new.md
  [ -z "$(git -C memory/org status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD:org)" = "$(git -C memory/org rev-parse HEAD)" ]
}

# The merge that follows takes A and B to rest: exit 0, both tiers recorded at
# their HEADs, root clean.
assert_take_converges() {
  drive_take_to_rest memory/ddaanet memory/org
  [ "$TAKE_STATUS" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ "$(git -C memory rev-parse HEAD:org)" = "$(git -C memory/org rev-parse HEAD)" ]
  [ -z "$(git -C memory status --porcelain --ignore-submodules=all)" ]
}

# A refusal that stays: status 1, the pin guard's line, /gitlore:merge named,
# A's gitlink untouched. $1 = A's pin.
assert_merge_refusal() {
  local pin="$1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a tier was moved off the commit the memory store records for it"* ]]
  [[ "$output" == *"Run /gitlore:merge"* ]]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin" ]
}

# A git on PATH that logs the directory of every `git -C <dir> fetch`.
make_fetch_log_git() {
  local real
  real=$(command -v git)
  mkdir -p "$TMP_REPO/stub"
  cat > "$TMP_REPO/stub/git" <<STUB
#!/bin/sh
if [ "\$1" = -C ] && [ "\$3" = fetch ]; then printf '%s\n' "\$2" >> "$TMP_REPO/fetch.log"; fi
exec "$real" "\$@"
STUB
  chmod 755 "$TMP_REPO/stub/git"
  : > "$TMP_REPO/fetch.log"
}

# How many fetches the stub logged for tier $1. The scripts run from the repo
# root and fetch with `git -C memory/<tier>`, so the logged directory is
# relative; an absolute one is matched too.
fetches_of() { grep -cE "(^|/)memory/$1\$" "$TMP_REPO/fetch.log" || true; }

# --- red: another tier is the refused store --------------------------------------

@test "red: A behind its pin, B dirty with arrivals, root dirty on live: the commit yields A and converges" {
  spaced_repo
  a_behind
  dirty_root
  b_arrivals
  b_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_a_yielded "$pin"
  assert_b_committed
  git -C memory cat-file -e HEAD:dirty.md
  assert_take_converges
}

@test "red: A ahead of its pin, B has an untracked file and arrivals, root clean: the commit yields A and converges" {
  spaced_repo
  a_ahead
  b_arrivals
  b_untracked
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_a_yielded "$pin"
  assert_b_committed
  assert_take_converges
}

@test "red: A ahead of its pin with upstream commits, B has a staged file and arrivals, root dirty on live: the commit yields A" {
  spaced_repo
  a_ahead_upstream
  dirty_root
  b_arrivals
  b_staged
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_a_yielded "$pin"
  assert_b_committed
  assert_take_converges
}

@test "red: A pinned at a commit it does not hold, B dirty with arrivals, root dirty on live: the commit yields A" {
  spaced_repo
  a_unheld
  dirty_root
  b_arrivals
  b_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_a_yielded "$pin"
  assert_b_committed
  assert_take_converges
}

@test "red: A forked from its live, B dirty with arrivals, root clean: the commit yields A and converges" {
  spaced_repo
  a_forked
  b_arrivals
  b_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_a_yielded "$pin"
  assert_b_committed
  assert_take_converges
}

@test "red: A behind its pin, B dirty with arrivals, root clean and forked from live: the commit yields A and converges" {
  spaced_repo
  a_behind
  fork_live_locally
  b_arrivals
  b_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_a_yielded "$pin"
  assert_b_committed
  assert_take_converges
}

# --- red: the off-pin tier is itself the refused store ----------------------------

@test "red: A behind its pin and dirty in its carrier, root dirty on live: the commit yields A and converges" {
  spaced_repo
  a_behind
  dirty_root
  a_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  before=$(git -C memory/ddaanet rev-parse HEAD)
  commit_following_compose
  assert_a_yielded "$pin"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$before" ]
  git -C memory/ddaanet cat-file -e HEAD:new.md
  assert_take_converges
}

@test "red: A behind its pin and dirty in its carrier, root clean: the commit yields A and converges" {
  spaced_repo
  a_behind
  a_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_a_yielded "$pin"
  git -C memory/ddaanet cat-file -e HEAD:new.md
  assert_take_converges
}

@test "red: A behind its pin and dirty in its carrier, root clean and forked from live: the commit yields A and converges" {
  spaced_repo
  a_behind
  fork_live_locally
  a_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_a_yielded "$pin"
  git -C memory/ddaanet cat-file -e HEAD:new.md
  assert_take_converges
}

@test "red: A ahead of its pin with upstream commits and dirty in its carrier, root dirty on live: the commit yields A" {
  spaced_repo
  a_ahead_upstream
  dirty_root
  a_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_a_yielded "$pin"
  git -C memory/ddaanet cat-file -e HEAD:new.md
  assert_take_converges
}

# --- red: each tier is fetched at most once per process -------------------------
#
# A fetch is the only way to learn whether a dirty tier whose local `live` is
# already in HEAD has something to take, so a process that decides whether the
# take would refuse fetches each such tier, and once. Nothing here has remote
# arrivals for A, and A is clean where it is not dirtied, so A is never fetched
# where it is clean.

@test "red: gitlore-compose with A behind and B dirty with arrivals fetches B once and A not at all" {
  spaced_repo
  a_behind
  dirty_root
  b_arrivals
  b_carrier_edit
  make_fetch_log_git
  PATH="$TMP_REPO/stub:$PATH" run bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
  [ "$(fetches_of org)" -eq 1 ]
  [ "$(fetches_of ddaanet)" -eq 0 ]
}

@test "red: one memory commit with A behind and B dirty with arrivals fetches B once" {
  spaced_repo
  a_behind
  dirty_root
  b_arrivals
  b_carrier_edit
  make_fetch_log_git
  PATH="$TMP_REPO/stub:$PATH" run commit_sections "memory: record"
  [ "$(fetches_of org)" -eq 1 ]
  [ "$(fetches_of ddaanet)" -eq 0 ]
}

@test "red: one memory commit with A ahead and dirty and B dirty, neither with arrivals, fetches each tier once" {
  spaced_repo
  a_ahead
  dirty_root
  a_carrier_edit
  b_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  make_fetch_log_git
  PATH="$TMP_REPO/stub:$PATH" run commit_sections "memory: record"
  # Nothing here is refused by the take, so nothing is yielded.
  assert_merge_refusal "$pin"
  [ "$(fetches_of ddaanet)" -eq 1 ]
  [ "$(fetches_of org)" -eq 1 ]
}

@test "red: the commit that goes through, after the compose it asked for, fetches B once" {
  spaced_repo
  a_behind
  dirty_root
  b_arrivals
  b_carrier_edit
  run bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
  make_fetch_log_git
  PATH="$TMP_REPO/stub:$PATH" run commit_sections "memory: record"
  [ "$status" -eq 0 ]
  [ "$(fetches_of org)" -eq 1 ]
  [ "$(fetches_of ddaanet)" -eq 0 ]
}

@test "red: gitlore-compose with A ahead and dirty and B dirty, neither with arrivals, fetches each tier once" {
  spaced_repo
  a_ahead
  dirty_root
  a_carrier_edit
  b_carrier_edit
  make_fetch_log_git
  PATH="$TMP_REPO/stub:$PATH" run bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
  [ "$(fetches_of ddaanet)" -eq 1 ]
  [ "$(fetches_of org)" -eq 1 ]
}

# --- lock-in: the take would not refuse, so the refusal stays ---------------------

@test "lock-in: A behind its pin, B dirty with nothing to take, root dirty on live: still refused naming /gitlore:merge" {
  spaced_repo
  a_behind
  dirty_root
  b_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_merge_refusal "$pin"
}

@test "lock-in: A behind its pin, B clean with arrivals, root dirty on live: still refused naming /gitlore:merge" {
  spaced_repo
  a_behind
  dirty_root
  b_arrivals
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_merge_refusal "$pin"
}

@test "lock-in: A behind its pin, B dirty whose remote cannot be fetched, root dirty on live: still refused naming /gitlore:merge" {
  spaced_repo
  a_behind
  dirty_root
  b_arrivals
  b_carrier_edit
  mv "$TMP_REPO/.bare-org.git" "$TMP_REPO/.bare-org.git.gone"
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  commit_following_compose
  assert_merge_refusal "$pin"
}

@test "lock-in: A beside its pin, B dirty with arrivals, root clean: still refused with the checkout remedy" {
  spaced_repo
  a_behind
  move_tier_off_pin ddaanet
  # Another ref holds HEAD, so the checkout strands nothing.
  git -C memory/ddaanet branch keep
  b_arrivals
  b_carrier_edit
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  run commit_sections "memory: record"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a tier was moved off the commit the memory store records for it"* ]]
  [[ "$output" == *"checkout --detach $pin"* ]]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin" ]
}

# --- lock-in: the fetch counter can count ------------------------------------------

# The scripts fetch as `git -C memory/<tier> fetch` from the repo root. A fetch
# of that shape through the stub is counted for its tier alone, so a count of
# zero in the tests above cannot be a stub or matcher that sees nothing.
@test "lock-in: the fetch counter reads a relative git -C fetch of one tier and no other" {
  spaced_repo
  a_behind
  make_fetch_log_git
  [ "$(fetches_of org)" -eq 0 ]
  PATH="$TMP_REPO/stub:$PATH" git -C memory/org fetch -q origin
  [ "$(fetches_of org)" -eq 1 ]
  [ "$(fetches_of ddaanet)" -eq 0 ]
}
