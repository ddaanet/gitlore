#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth
load helpers/tier-fixtures
load helpers/resolve-recovery

@test "recovery: after the recovery, a memory commit runs to completion instead of aborting on the pin guard" {
  tier_prepare_head_vs_live ddaanet

  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  git -C memory/ddaanet checkout -q --detach live

  # A fresh approval for the memory commit this recovery is supposed to
  # unblock. Item 1.2 aborts a commit whose tier sits off the pin memory's
  # index records; the per-tier merge-state guard runs ahead of that pin check
  # in the very same function, so the recovery above is what has to bring the
  # two back into agreement before the pin guard ever looks.
  printf 'memory: adopt the tier merge\n' > "$(gitlore_commit_msg_file memory)"
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]
}

@test "recovery: a staging failure for a landed tier merge is reported, and the recovery still returns 0" {
  export GITLORE_GIT_RETRY_SCHEDULE="0 0"
  tier_prepare_head_vs_live ddaanet

  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  git -C memory/ddaanet checkout -q --detach live

  # --absolute-git-dir: a submodule's plain --git-dir is resolved against the
  # store, not the cwd this writes the lock from.
  mem_gitdir=$(git -C memory rev-parse --absolute-git-dir)
  : > "$mem_gitdir/index.lock"
  run --separate-stderr gitlore_guard_stale_merge_state memory/ddaanet
  rm -f "$mem_gitdir/index.lock"

  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ]
  [[ "$stderr" == *"could not be staged"* ]]
  # The printed staging command runs verbatim, from outside the project.
  line=$(printf '%s\n' "$stderr" | grep -F 'could not be staged')
  cmd=${line#*\`}
  cmd=${cmd%%\`*}
  (cd / && eval "$cmd")
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]
}

# BORN-GREEN, like case 3 above: unchanged code stages nothing anywhere, so this
# holds today and is a regression pin rather than a red.
#
# A host project is not a memory store just for keeping a MEMORY.md at its root,
# and its gitlink to `memory` is the pre-commit hook's to move under FR11 —
# staging it here would put a pointer move into the user's own project index
# outside every approval gate.
#
# What the predicate cannot be: "the superproject carries a root MEMORY.md AND
# the store's path is in `gitlore_tier_paths "$super"`". `gitlore_tier_paths`
# (scripts/lib/util.sh:360) prints every submodule path a repo registers, with
# no notion of a tier beyond enclosure, so the memory store satisfies the second
# condition inside its OWN host — and this fixture's host satisfies the first.
# The discriminating clause is the third: the store's path must not be the
# superproject's own `submodule.gitlore-memory.path`.
#
# MUTATION PROOF, for code review — drop that third clause, leaving the
# two-condition predicate this item specified before the correction, and watch
# THIS case red. (Reported as M1c; the one-clause form, MEMORY.md alone, reds it
# too.) Case 3 is the pin on the other clauses and stays green under it, so this
# case is what isolates the exclusion.
#
# The guard runs from a cwd OUTSIDE the superproject on purpose:
# `gitlore_memory_path` (scripts/lib/util.sh:83) reads `.gitmodules` from the
# CURRENT DIRECTORY, not from a repo it is handed, so a GREEN that reaches for
# it instead of `git config --file "$super/.gitmodules" …` finds no
# registration, skips the exclusion and stages. Run from $TMP_REPO that bug is
# invisible; run from anywhere else it reds this case (reported as M3).
@test "recovery: a host project that keeps a root MEMORY.md is not a memory store" {
  make_diverged_head_vs_live memory
  # The only addition to case 3's fixture. It lands in the parent working tree
  # and goes with the whole tree in teardown_tmp_repo's `rm -rf`, so there is no
  # cleanup line here to trip errexit whatever a fixed implementation does with
  # the file.
  printf '# host project notes\n' > MEMORY.md
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]

  GITLORE_MEMORY_COMMIT=1 git -C memory commit -q --no-edit
  landed=$(git -C memory rev-parse HEAD)
  git -C memory checkout -q --detach live

  before=$(git -C "$TMP_REPO" diff --cached --name-only)
  cd "$BATS_TEST_TMPDIR"
  run --separate-stderr gitlore_guard_stale_merge_state "$TMP_REPO/memory"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TMP_REPO/memory" rev-parse HEAD)" = "$landed" ]
  [ "$(git -C "$TMP_REPO" diff --cached --name-only)" = "$before" ]
}

# Staging the moved gitlink is only half of the adoption, and the other half is
# what makes it safe. An index that agrees with the tier's HEAD is exactly the
# disagreement gitlore_compose_check_pins refuses on, so a recovery that only
# stages lets the very next pass run its DOWN projection over a carrier holding
# what the merge brought in — turning the loud abort above into a silent
# overwrite of upstream text nobody here approved away.
#
# The `live` side edits the TEXT of an index line BOTH surfaces already carry.
# That is deliberate and load-bearing: the down projection keeps a line only the
# carrier holds (root at HEAD never had it), so an upstream ADDITION leaves this
# case green against the destructive implementation and proves nothing.
#
# MUTATION PROOF, for code review — drop the gitlore_compose_up call from
# gitlore_adopt_recovered_merge, leaving the bare staging, and watch the carrier
# assertion red with root's superseded text.
@test "recovery: the upstream text a landed tier merge brought in survives the commit that adopts it" {
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live

  # A fact both indexes carry, established through the real commit path so
  # root's block holds root's own copy of the line.
  seed_tier_bullet ddaanet shared.md "ours"
  printf 'memory: record the shared fact\n' > "$(gitlore_commit_msg_file memory)"
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 0 ]
  assert_bullets memory/MEMORY.md '- [shared](ddaanet/shared.md) — ours'
  base=$(git -C memory/ddaanet rev-parse HEAD)

  # Another consumer re-texts that same line and publishes it on the tier's
  # `live`. Built with plumbing, like advance_branch_with_file, because what has
  # to change is a tracked file's CONTENT rather than a new path.
  sed '$d' memory/ddaanet/MEMORY.md > "$BATS_TEST_TMPDIR/up-carrier"
  printf -- '- [shared](shared.md) — upstream text\n' >> "$BATS_TEST_TMPDIR/up-carrier"
  blob=$(git -C memory/ddaanet hash-object -w --stdin < "$BATS_TEST_TMPDIR/up-carrier")
  idx=$(mktemp "$BATS_TEST_TMPDIR/idx.XXXXXX"); rm -f "$idx"
  tree=$(
    GIT_INDEX_FILE="$idx" git -C memory/ddaanet read-tree "$base" &&
    GIT_INDEX_FILE="$idx" git -C memory/ddaanet update-index \
      --cacheinfo "100644,$blob,MEMORY.md" &&
    GIT_INDEX_FILE="$idx" git -C memory/ddaanet write-tree
  )
  rm -f "$idx"
  up=$(git -C memory/ddaanet -c user.email=t@t -c user.name=t \
    commit-tree "$tree" -p "$base" -m "upstream re-text")
  git -C memory/ddaanet update-ref refs/heads/live "$up"

  # The local side is a BODY file, so the tier's own commit touches no index
  # line and the merge below cannot conflict on the one under test.
  printf 'body\n' > memory/ddaanet/local-body.md
  printf 'memory: local body fact\n' > "$(gitlore_commit_msg_file memory)"
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]

  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  git -C memory/ddaanet checkout -q --detach live
  # The merge result, before the commit path is allowed near it.
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — upstream text'

  printf 'memory: adopt the tier merge\n' > "$(gitlore_commit_msg_file memory)"
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 0 ]
  # The carrier still holds what the merge landed …
  assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — upstream text'
  # … and root took it up, so the line above is the adoption's result and not a
  # composition that quietly declined to run. Both ahead of the pin equality:
  # the overwrite this case exists to catch also moves the pin (composing over
  # the carrier dirties the tier, and the tier loop then commits it), so a pin
  # assertion first would make the case red one step away from its own point.
  assert_bullets memory/MEMORY.md '- [shared](ddaanet/shared.md) — upstream text'
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]
}

# The other half of the same rule: when the up projection CANNOT run, nothing
# may be staged either. Staging the gitlink alone is what puts the enclosing
# index back in agreement with the tier's HEAD, and that agreement is the only
# thing standing between the down projection and a carrier root has not adopted
# — so a root index too broken to take the tier's lines must keep the pin
# guard's refusal rather than trade it for a silent overwrite.
#
# The refusal is induced through gitlore_compose_check's rule 3: a root bullet
# prefixed with a tier that is not mounted. That is a real state (a tier removed
# from .gitmodules with its lines left behind), reached by writing one line.
#
# MUTATION PROOF, for code review — stage the pair even when gitlore_compose_up
# returns non-zero, and watch the pin assertion red.
@test "recovery: a landed tier merge the root index cannot take is left unstaged" {
  tier_prepare_head_vs_live ddaanet
  pin_before=$(git -C memory rev-parse ":ddaanet")

  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$landed" != "$pin_before" ]
  git -C memory/ddaanet checkout -q --detach live
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"

  run --separate-stderr gitlore_guard_stale_merge_state memory/ddaanet
  [ "$status" -eq 0 ]
  # Nothing staged, so the pin guard downstream still has its refusal.
  [ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ]
  [[ "$stderr" == *"could not take"* ]]
}

@test "recovery: a checkout-cleared merge whose HEAD is not the authority names both shas" {
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  head_at=$(git -C memory rev-parse HEAD)
  echo "synthesized" > memory/SYNTH.md
  git -C memory add -A
  git -C memory checkout -q --detach HEAD
  # `live` moves under the prepared merge, so the authority the state file names
  # is no longer the commit the merge was built on.
  advance_branch_with_file memory live MOVED.md moved "live moved on" live
  moved=$(git -C memory rev-parse live)

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [[ "$all" == *"$head_at"* ]]
  [[ "$all" == *"$moved"* ]]
  # Nothing was guessed at: the staged tree and the state file are as they were.
  [ -f "$(gitlore_merge_state_file memory)" ]
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD || true)" ]
}

@test "recovery: a stale merge state naming no pending commit is reported, not guessed at" {
  printf '{"flavor":"head-vs-live","store":"%s"}\n' "$(cd memory && pwd)" \
    > "$(gitlore_merge_state_file memory)"

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [[ "$all" == *"manual intervention required"* ]]
  # It says WHY it cannot classify: neither handle on the pending side is there.
  [[ "$all" == *"$GITLORE_PENDING_REF"* ]]
  [[ "$all" == *"source_ref"* ]]
  [ -f "$(gitlore_merge_state_file memory)" ]
}
