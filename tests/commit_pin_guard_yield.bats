#!/usr/bin/env bats
# The commit path's pin guard (rule 7) yields where its own remedy,
# /gitlore:merge, would refuse the memory root: root holds uncommitted work the
# take counts and its HEAD has forked from its local `live`. A tier that is
# ahead of its pin, behind it, or pinned at a commit it does not hold is then
# left recorded where root has it; the commit records root's own changes, says
# /gitlore:merge is next, and the merge that follows converges. Outside that
# state the refusal stands, and a tier beside its pin keeps its checkout remedy.
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

# Root's own uncommitted fact and its tier's, each with an index line.
dirty_tier_fact() {
  seed_tier_bullet ddaanet new.md "an uncommitted tier fact"
  seed_root_bullet ddaanet/new.md "an uncommitted tier fact"
}

# Tier ahead of its pin: the carrier gained upstream.md past the recorded commit.
ahead_state() {
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet loc.md
  move_tier_off_pin_into_live ddaanet
}

# Tier on its pin: the shared base store.
on_pin_state() { take_base_store ddaanet; }

# Tier behind its pin: checked out one commit before the recorded one.
behind_state() {
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet loc.md
  git -C memory/ddaanet checkout -q --detach HEAD~1
}

# Root records a tier commit (with a file and its carrier line) that this
# checkout lacks, with the root line the recording checkout composed for it; the
# tier remote holds it. Leaves its sha in TIER_UP.
unheld_state() {
  local work
  take_base_store ddaanet
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
  TIER_UP=$(git -C "$work" rev-parse HEAD)
  rm -rf "$work"
  git -C memory update-index --cacheinfo "160000,$TIER_UP,ddaanet"
  seed_root_bullet ddaanet/up.md "published upstream"
  git -C memory add MEMORY.md
  git -C memory commit -qm "another checkout recorded ddaanet"
  git -C memory push -q . HEAD:refs/heads/live
  if git -C memory/ddaanet cat-file -e "$TIER_UP^{commit}"; then
    echo "fixture: the tier holds its pin" >&2
    return 1
  fi
}

# Succeeds when HEAD's root index has a line pointing at $1.
head_index_has() { git -C memory show HEAD:MEMORY.md | grep -qF "]($1)"; }

# State (c): the tier state $1, memory's HEAD forked from `live`, root dirty.
state_c() {
  "$1"
  fork_live_locally
  dirty_root
}

# The commit yielded: exit 0, root's own change recorded, the tier's gitlink
# neither recorded nor staged, /gitlore:merge named, no refusal and no orphan
# advice. $1 is the gitlink root recorded before the commit.
assert_yielded() {
  local pin="$1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tier 'ddaanet' is checked out off the commit the memory store records for it, so this commit recorded root's own changes and left the tier unrecorded. Run /gitlore:merge next"* ]]
  [[ "$output" != *"a tier was moved off the commit the memory store records"* ]]
  [[ "$output" != *"is in the tier but not in the root index"* ]]
  git -C memory cat-file -e HEAD:dirty.md
  git -C memory show HEAD:MEMORY.md | grep -qF '](dirty.md)'
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin" ]
  [ -z "$(git -C memory diff --cached --name-only -- ddaanet)" ]
}

# Merge, land the prepared root merge, merge again: exit 0 with the tier
# recorded at its HEAD, which is $1 when given, and root clean.
assert_converges() {
  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ -z "${1:-}" ] || [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$1" ]
  [ -z "$(git -C memory status --porcelain --ignore-submodules=all)" ]
  git -C memory show HEAD:MEMORY.md | grep -qF '](dirty.md)'
}

@test "yield: a tier ahead of its pin, dirty forked root, converges" {
  spaced_repo
  state_c ahead_state
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  tier=$(git -C memory/ddaanet rev-parse HEAD)
  run ! grep -qF '](ddaanet/upstream.md)' memory/MEMORY.md
  run commit_sections "memory: record dirty"
  assert_yielded "$pin"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier" ]
  run ! head_index_has ddaanet/upstream.md
  assert_converges "$tier"
  grep -qF '](ddaanet/upstream.md)' memory/MEMORY.md
  git -C memory show HEAD:MEMORY.md | grep -qF '](ddaanet/upstream.md)'
}

@test "yield: a tier behind its pin, dirty forked root, converges" {
  spaced_repo
  state_c behind_state
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$pin" ]
  run commit_sections "memory: record dirty"
  assert_yielded "$pin"
  assert_converges "$pin"
  git -C memory show HEAD:MEMORY.md | grep -qF '](ddaanet/loc.md)'
}

@test "yield: a tier pinned at a commit it does not hold, dirty forked root, converges" {
  spaced_repo
  state_c unheld_state
  run commit_sections "memory: record dirty"
  assert_yielded "$TIER_UP"
  assert_converges "$TIER_UP"
  grep -qF '](ddaanet/up.md)' memory/MEMORY.md
  git -C memory show HEAD:MEMORY.md | grep -qF '](ddaanet/up.md)'
}

@test "yield: a dirty tier is committed under its own section, its gitlink stays unrecorded, and the merge converges" {
  spaced_repo
  state_c ahead_state
  seed_tier_bullet ddaanet new.md "an uncommitted tier fact"
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  before=$(git -C memory/ddaanet rev-parse HEAD)
  run commit_sections "memory: record dirty"
  assert_yielded "$pin"
  after=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$after" != "$before" ]
  git -C memory/ddaanet cat-file -e HEAD:new.md
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  assert_converges "$after"
  head_index_has ddaanet/upstream.md
  head_index_has ddaanet/new.md
}

# The yield set is read before the tiers are committed: a tier on its pin with
# uncommitted work is not in it, so the commit records the tier's new commit.
@test "yield: a dirty tier on its pin, committed by a yielding run on a dirty forked root, is recorded" {
  spaced_repo
  state_c on_pin_state
  dirty_tier_fact
  # Tier lines sort ahead of root's own, so the fixture composes before the commit.
  bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  [ "$pin" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  run commit_sections "memory: record dirty"
  [ "$status" -eq 0 ]
  after=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$after" != "$pin" ]
  git -C memory/ddaanet cat-file -e HEAD:new.md
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$after" ]
  git -C memory cat-file -e HEAD:dirty.md
}

@test "yield: root edits that need a compose pass do not send the commit through gitlore-compose and back" {
  spaced_repo
  state_c ahead_state
  dirty_tier_fact
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  # When a pass would change an index, the commit asks for gitlore-compose, and
  # that must not refuse; otherwise the commit yields at once.
  run commit_sections "memory: record dirty"
  if [[ "$output" == *"Run gitlore-compose"* ]]; then
    run bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"ahead of the commit the memory store records"* ]]
    run commit_sections "memory: record dirty"
  fi
  assert_yielded "$pin"
  assert_converges
  head_index_has ddaanet/new.md
}

@test "yield: gitlore-compose does not refuse a yielded tier on its own" {
  spaced_repo
  state_c ahead_state
  run bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ahead of the commit the memory store records"* ]]
}

@test "yield: the tier's own section commit stages no gitlink in root" {
  spaced_repo
  state_c ahead_state
  seed_tier_bullet ddaanet new.md "an uncommitted tier fact"
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  run commit_sections "memory: record dirty"
  [ "$status" -eq 0 ]
  [ -z "$(git -C memory diff --cached --name-only)" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$pin" ]
}

@test "yield: the pass does not project root's text over a yielded tier's reword" {
  spaced_repo
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet loc.md
  # The tier rewords a line root holds, past the commit root records.
  sed 's/(loc.md) — committed here/(loc.md) — reworded in the tier/' \
    memory/ddaanet/MEMORY.md > "$BATS_TEST_TMPDIR/carrier"
  cp "$BATS_TEST_TMPDIR/carrier" memory/ddaanet/MEMORY.md
  git -C memory/ddaanet commit -qam "reword loc"
  git -C memory/ddaanet push -q . HEAD:refs/heads/live
  fork_live_locally
  dirty_root
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  carrier=$(cat memory/ddaanet/MEMORY.md)
  [[ "$carrier" == *"(loc.md) — reworded in the tier"* ]]
  run bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
  [ "$status" -eq 0 ]
  [ "$(cat memory/ddaanet/MEMORY.md)" = "$carrier" ]
  run commit_sections "memory: record dirty"
  assert_yielded "$pin"
  [ "$(cat memory/ddaanet/MEMORY.md)" = "$carrier" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  git -C memory show HEAD:MEMORY.md | grep -qF '](ddaanet/loc.md) — committed here'
  assert_converges
  git -C memory show HEAD:MEMORY.md | grep -qF '](ddaanet/loc.md) — reworded in the tier'
}

# Rule 7's own mid-merge line reaches gitlore-compose; the commit meets the merge
# at its stale-merge guard first.
@test "guard: a mid-merge tier off its pin on a dirty forked root is still refused naming /gitlore:resolve" {
  spaced_repo
  state_c ahead_state
  gd=$(git -C memory/ddaanet rev-parse --absolute-git-dir)
  git -C memory/ddaanet rev-parse HEAD > "$gd/MERGE_HEAD"
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  run bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tier 'ddaanet' is mid-merge and sits off the commit the memory store records for it; run /gitlore:resolve"* ]]
  # The commit answers the merge ahead of rule 7, with the stale-merge guard.
  run commit_sections "memory: record dirty"
  [ "$status" -eq 1 ]
  [[ "$output" == *"memory/ddaanet holds a merge gitlore did not prepare"* ]]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin" ]
}

# --- guards that do not change ----------------------------------------------

@test "guard: a tier ahead of its pin on a dirty root whose HEAD is on live is still refused naming /gitlore:merge" {
  spaced_repo
  ahead_state
  dirty_root
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  run commit_sections "memory: record dirty"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a tier was moved off the commit the memory store records for it"* ]]
  [[ "$output" == *"Run /gitlore:merge"* ]]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin" ]
}

@test "guard: a tier ahead of its pin with no content change of its own in a forked root is still refused" {
  spaced_repo
  ahead_state
  fork_live_locally
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  run commit_sections "memory: record"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a tier was moved off the commit the memory store records for it"* ]]
  [[ "$output" == *"Run /gitlore:merge"* ]]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin" ]
}

@test "guard: a tier beside its pin on a dirty forked root keeps its checkout remedy" {
  spaced_repo
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet loc.md
  git -C memory/ddaanet checkout -q --detach HEAD~1
  move_tier_off_pin ddaanet
  # Another ref holds HEAD, so the checkout strands nothing.
  git -C memory/ddaanet branch keep
  fork_live_locally
  dirty_root
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  run commit_sections "memory: record dirty"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a tier was moved off the commit the memory store records for it"* ]]
  [[ "$output" == *"$(git -C memory/ddaanet rev-parse HEAD | cut -c1-12)"* ]]
  [[ "$output" == *"checkout --detach $pin"* ]]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin" ]
}

# --- a tier forked from its own `live` ------------------------------------------

# Behind its pin with work of its own: the yielded commit lands that work on the
# tier's HEAD, which leaves it beside the pin, forked from its `live`.
@test "forked: a tier the yield commit leaves beside its pin is never told to check out, and its commit is recorded" {
  spaced_repo
  state_c behind_state
  seed_tier_bullet ddaanet new.md "an uncommitted tier fact"
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  run commit_sections "memory: record dirty"
  assert_yielded "$pin"
  tc=$(git -C memory/ddaanet rev-parse HEAD)
  git -C memory/ddaanet cat-file -e "$tc:new.md"
  run bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
  [[ "$output" != *"checkout --detach"* ]]
  [ "$status" -eq 1 ]
  [[ "$output" == *"Run /gitlore:merge"* ]]
  printf 'x\n' > memory/more.md
  seed_root_bullet more.md "another root fact"
  run commit_sections "memory: another"
  [ "$status" -eq 0 ]
  [[ "$output" != *"checkout --detach"* ]]
  [[ "$output" == *"left the tier unrecorded. Run /gitlore:merge next"* ]]
  assert_converges
  git -C memory/ddaanet merge-base --is-ancestor "$tc" "$(git -C memory rev-parse HEAD:ddaanet)"
  head_index_has ddaanet/new.md
}

# The same shape made by hand, on a dirty forked root: the commit yields it.
@test "forked: a hand commit forked from the tier's live, dirty forked root, yields and converges" {
  spaced_repo
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet loc.md
  git -C memory/ddaanet checkout -q --detach HEAD~1
  move_tier_off_pin ddaanet
  tc=$(git -C memory/ddaanet rev-parse HEAD)
  fork_live_locally
  dirty_root
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  run commit_sections "memory: record dirty"
  [[ "$output" != *"checkout --detach"* ]]
  assert_yielded "$pin"
  assert_converges
  git -C memory/ddaanet merge-base --is-ancestor "$tc" "$(git -C memory rev-parse HEAD:ddaanet)"
}

# Re-authored past the pin: `live` holds the pin's parent, not the pin, so the
# take would only advance `live`; the checkout stays the remedy.
@test "guard: a tier re-authored beside its pin keeps its checkout remedy" {
  spaced_repo
  take_base_store ddaanet
  move_tier_diverged_off_pin ddaanet
  fork_live_locally
  dirty_root
  pin=$(git -C memory rev-parse :ddaanet)
  run commit_sections "memory: record dirty"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checkout --detach $pin"* ]]
  run bash "$PLUGIN_ROOT/scripts/compose-memory.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"checkout --detach $pin"* ]]
}
