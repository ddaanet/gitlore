#!/usr/bin/env bats
# Composition at the merge continuation.
#
# A landed merge is the one write path into a memory store that no compose
# trigger sees: the PostToolBatch hook fires on an index EDIT, SessionStart on a
# new session. A synthesized index used to sit uncomposed until one of those
# happened to fire; now the continuation composes before it commits, so the
# composed bytes are IN the merge commit.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"
PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"
RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

approve() { printf '%s\n' "$1" > "$(gitlore_commit_msg_file memory)"; }

mount_tier_at_live() {
  local tier="${1:-ddaanet}"
  make_tier_in_memory "$tier"
  git -C "memory/$tier" fetch -q origin "live:live"
  git -C "memory/$tier" checkout -q --detach live
}

# Commit $1 as the root index on the detached memory HEAD, then move `live`
# sideways — the head-vs-live shape, carrying the index the merge must compose.
diverge_memory_with_index() {
  printf '%s\n' "$1" > memory/MEMORY.md
  (
    cd memory || exit 1
    git add -A
    GITLORE_MEMORY_COMMIT=1 git -c user.email=t@t -c user.name=t commit -q -m "Pending index"
  )
  advance_branch_with_file memory live LIVE.md live-side "Live commit"
  echo parent > parent-file
  git add parent-file
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

@test "the continuation composes the merged root index into the merge commit" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  # A root-authored tier line with no prior compose: the base is empty, so the
  # merge is a union and the line mirrors down as a fresh add.
  # The project line precedes the tier line, which composition is what reorders:
  # if the committed index is tier-block-first, the pass ran before the commit.
  diverge_memory_with_index '# Memory Index

- [P](p.md) — project
- [T](ddaanet/x.md) — org'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]

  committed=$(git -C memory show HEAD:MEMORY.md)
  [[ "$committed" == *"- [T](ddaanet/x.md) — org"$'\n'"- [P](p.md) — project"* ]]
  # The pass writes the root index only, so the carrier is NOT touched:
  # projecting down would push a line into a second store as a side effect of
  # approving this merge, and the user approved one index.
  run grep -qxF -- '- [T](x.md) — org' memory/ddaanet/MEMORY.md
  [ "$status" -ne 0 ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
}

@test "a tier merge splices its merged carrier lines up into the root index" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  push_tier_fact ddaanet "- [their fact](t.md) — theirs" >/dev/null

  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  mem_before=$(git -C memory rev-parse HEAD)

  # Stand in for the memory-merger sub-agent: synthesize both sides, then add.
  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [org fact](f.md) — ours\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]

  # The merged carrier reached the root index, prefixed.
  grep -qxF -- '- [org fact](ddaanet/f.md) — ours' memory/MEMORY.md
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
  # The tier carries the merge commit; the root carries a bookkeeping commit of
  # its own for the recomposed index and the moved gitlink, so an explicit
  # operation leaves a clean store (D49).
  [ "$(git -C memory rev-parse HEAD)" != "$mem_before" ]
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory log -1 --format=%s)" = "Update MEMORY.md for ddaanet tier merge." ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
}

# Prepare a tier merge and synthesize it, leaving the continuation to run. Both
# sides add a line to the carrier, so the landed merge holds text root lacks.
# $1 = the command whose refusal prepares the merge (default: pre-push).
prepare_tier_merge_with_new_lines() {
  local preparer="${1:-$PRE_PUSH}"
  make_parent_with_memory
  # The fixture's memory remote has no `live` yet, and a take fetches it.
  git -C memory push -q origin live
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  push_tier_fact ddaanet "- [their fact](t.md) — theirs" >/dev/null
  bash "$preparer" && return 1
  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [org fact](f.md) — ours\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A
}

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

@test "a compose refusal is reported but never strands the merge" {
  make_parent_with_memory
  diverge_memory_with_index '# Memory Index

- [P](p.md) — one
- [P again](p.md) — two'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]
  all="${output}${stderr}"
  [[ "$all" == *"composition refused"* ]]
  [[ "$all" == *"duplicate pointer path p.md"* ]]

  # The merge landed anyway, uncomposed and unmangled: both lines intact, the
  # state file gone, `live` on the merge commit.
  committed=$(git -C memory show HEAD:MEMORY.md)
  [[ "$committed" == *"- [P](p.md) — one"* ]]
  [[ "$committed" == *"- [P again](p.md) — two"* ]]
  [ ! -f "$(gitlore_merge_state_file memory)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$(git -C memory rev-parse live)" ]
}

@test "a dangling pointer in the merged index is reported, not repaired" {
  make_parent_with_memory
  diverge_memory_with_index '# Memory Index

- [Gone](gone.md) — the file this names is not there'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]
  all="${output}${stderr}"
  [[ "$all" == *"gone.md names no file in the memory store"* ]]
  [[ "$all" == *"Nothing was rewritten or deleted"* ]]

  # Reported only: the line survives into the commit and no file was created.
  [[ "$(git -C memory show HEAD:MEMORY.md)" == *"- [Gone](gone.md)"* ]]
  [ ! -e memory/gone.md ]
}

@test "a tier merge on a store with no root index commits, reports, and stages the gitlink" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  # A store the installer seeded from an empty auto-memory dir: no MEMORY.md at
  # all. Composition tolerates that; the continuation's staging step must too.
  git -C memory rm -q MEMORY.md
  GITLORE_MEMORY_COMMIT=1 git -C memory -c user.email=t@t -c user.name=t commit -q -m "No root index"
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  push_tier_fact ddaanet "- [their fact](t.md) — theirs" >/dev/null

  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  tier_before=$(git -C memory/ddaanet rev-parse HEAD)

  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [org fact](f.md) — ours\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
[[ "$stderr" == *"no MEMORY.md"* ]]

  # The tier merge landed, and the moved gitlink is staged in the root store.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$tier_before" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ ! -f memory/MEMORY.md ]
}
