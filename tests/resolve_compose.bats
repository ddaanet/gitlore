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

# Rewrite the synthesized ddaanet carrier with one pointer twice, so the merged
# index fails the check on the carrier itself.
duplicate_tier_carrier() {
  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [their fact](t.md) — theirs\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A
}

# The head-vs-live counterpart to prepare_tier_merge_with_new_lines: the tier
# diverges from its own local `live`, as tier_divergence.bats's pre-commit
# preparation does, rather than from its remote, so pre-commit prepares the
# merge instead of pre-push.
prepare_tier_merge_head_vs_live() {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT" && return 1
  return 0
}

@test "a tier merge whose merged carrier has a duplicate pointer is not committed" {
  prepare_tier_merge_with_new_lines
  [ "$(jq -r .flavor "$(gitlore_merge_state_file memory/ddaanet)")" = "head-vs-remote" ]
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  mem_before=$(git -C memory rev-parse HEAD)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root-before"
  duplicate_tier_carrier

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md: duplicate pointer path t.md"* ]]
  [ -f "$(gitlore_merge_state_file memory/ddaanet)" ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  cmp -- "$BATS_TEST_TMPDIR/root-before" memory/MEMORY.md
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "a head-vs-live tier merge whose merged carrier has a duplicate pointer is not committed" {
  prepare_tier_merge_head_vs_live
  [ "$(jq -r .flavor "$(gitlore_merge_state_file memory/ddaanet)")" = "head-vs-live" ]
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  mem_before=$(git -C memory rev-parse HEAD)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root-before"
  duplicate_tier_carrier

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md: duplicate pointer path t.md"* ]]
  [ -f "$(gitlore_merge_state_file memory/ddaanet)" ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  cmp -- "$BATS_TEST_TMPDIR/root-before" memory/MEMORY.md
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "a kept refused merge re-emits the continuation directive" {
  prepare_tier_merge_with_new_lines
  duplicate_tier_carrier
  run bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"continue-after-merge"* ]]
}

@test "a fixed merged carrier lands" {
  prepare_tier_merge_with_new_lines
  duplicate_tier_carrier
  run bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]

  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [their fact](t.md) — theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  merged=$(git -C memory/ddaanet rev-parse HEAD)
  git -C memory/ddaanet rev-parse -q --verify "$merged^2" >/dev/null
  run ! git -C memory/ddaanet rev-parse -q --verify "$merged^3"
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$merged" ]
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
}

@test "a refused tier merge answers an unapproved parent commit with its continuation directive" {
  # The kept merge moves the tier's gitlink, so memory reads dirty with no
  # fresh approval. The merge speaks first: a summary request would put a
  # merge in front of the user, and nothing may commit on top of it anyway.
  prepare_tier_merge_with_new_lines
  duplicate_tier_carrier
  run bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  mem_before=$(git -C memory rev-parse HEAD)
  [ "$(gitlore_commit_msg_freshness memory)" != "yes" ]

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 1 ]
  all="${output}${stderr}"
  [[ "$all" == *"memory merge prepared"* ]]
  [[ "$all" == *"continue-after-merge"* ]]
  [[ "$all" != *"no approved commit summary"* ]]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "a tier merge whose incoming side welds a line is refused, and the split synthesis publishes" {
  # A weld that arrives on the far side of a divergence reaches a synthesis,
  # not a take, so it is re-authored rather than repaired: the entry-wise pass
  # carries the welded line through as one bullet, the gate refuses it, and the
  # split lands and reaches the tier's remote.
  make_parent_with_memory
  git -C memory push -q origin live
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  printf -- '- [org fact](f.md) — ours\n' >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  push_tier_fact ddaanet "- [their fact](t.md) — theirs- [their other](u.md) — also theirs" >/dev/null
  run bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  git -C memory/ddaanet add -A

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md: line "*" welds two pointer bullets onto one line — u.md"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]

  printf -- '---\ndescription: "org-wide facts"\n---\n\n# ddaanet tier index\n\n- [org fact](f.md) — ours\n- [their fact](t.md) — theirs\n- [their other](u.md) — also theirs\n' \
    > memory/ddaanet/MEMORY.md
  git -C memory/ddaanet add -A
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" show live:MEMORY.md > "$BATS_TEST_TMPDIR/published"
  grep -qxF -- '- [their other](u.md) — also theirs' "$BATS_TEST_TMPDIR/published"
  grep -qxF -- '- [their other](ddaanet/u.md) — also theirs' memory/MEMORY.md
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

@test "a duplicate in the merged root index keeps the merge unlanded" {
  make_parent_with_memory
  diverge_memory_with_index '# Memory Index

- [P](p.md) — one
- [P again](p.md) — two'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  mem_before=$(git -C memory rev-parse HEAD)
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/MEMORY.md: duplicate pointer path p.md"* ]]
  [ -f "$(gitlore_merge_state_file memory)" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "a memory-root merge whose merged index welds a line is not committed" {
  make_parent_with_memory
  diverge_memory_with_index '# Memory Index

- [A](a.md) — a- [B](b.md) — b'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  mem_before=$(git -C memory rev-parse HEAD)
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"was not committed"* ]]
  [[ "$stderr" == *"memory/MEMORY.md: line "*" welds two pointer bullets"* ]]
  [ -f "$(gitlore_merge_state_file memory)" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$mem_before" ]
}

@test "a memory-root merge with only a leftover root prefix commits uncomposed" {
  make_parent_with_memory
  diverge_memory_with_index '# Memory Index

- [Old fact](gone/x.md) — a tier that is no longer mounted'

  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]
  all="${output}${stderr}"
  [[ "$all" == *"committed uncomposed"* ]]
  [[ "$all" == *"gone/x.md"* ]]
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
  # A store migrated from an auto-memory dir that held no MEMORY.md: no root
  # index at all. Composition tolerates that; the continuation's staging step
  # must too.
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
