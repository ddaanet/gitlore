#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# Each @test is its own subshell, and tier_prepare_head_vs_live's `run` is
# consumed within that same test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth
load helpers/tier-fixtures

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"
PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}
teardown() { teardown_tmp_repo; }

@test "recovery: a prepared merge met by a later gate is continued, not discarded" {
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  statefile=$(gitlore_merge_state_file memory)
  pending=$(git -C memory rev-parse "$GITLORE_PENDING_REF")
  # What the merger sub-agent staged before the session ended: a file no
  # auto-merge of the two sides produces, so its survival is unambiguous.
  printf 'synthesized by the merger\n' > memory/SYNTH.md
  git -C memory add -A
  state_before=$(cat "$statefile")

  # A gate meeting the prepared merge in a later session.
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  all="$output$stderr"
  [[ "$all" == *"continue-after-merge"* ]]
  # Everything the sub-agent would resume from is exactly where it left it.
  [ "$(git -C memory rev-parse MERGE_HEAD)" = "$pending" ]
  git -C memory diff --cached --name-only | grep -qx 'SYNTH.md'
  [ "$(cat "$statefile")" = "$state_before" ]
  [ "$(git -C memory rev-parse "$GITLORE_PENDING_REF")" = "$pending" ]
}

@test "recovery: /gitlore:resolve continues a prepared merge rather than re-preparing it" {
  # The skill's standalone entry: no directive reached an agent, so the script
  # is run bare. It needs a remote carrying `live` to get past its early
  # repairs and reach the stale-state guard.
  git -C memory push -q origin live
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  pending=$(git -C memory rev-parse "$GITLORE_PENDING_REF")
  printf 'synthesized by the merger\n' > memory/SYNTH.md
  git -C memory add -A

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  all="$output$stderr"
  [[ "$all" == *"continue-after-merge"* ]]
  [ "$(git -C memory rev-parse MERGE_HEAD)" = "$pending" ]
  git -C memory diff --cached --name-only | grep -qx 'SYNTH.md'
}

@test "recovery: a merge prepared in an earlier session lands through the continuation" {
  git -C memory push -q origin live
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  live_before=$(git -C memory rev-parse live)
  pending=$(git -C memory rev-parse "$GITLORE_PENDING_REF")
  printf 'synthesized by the merger\n' > memory/SYNTH.md
  git -C memory add -A

  run --separate-stderr bash "$PRE_COMMIT"
  [[ "$output$stderr" == *"continue-after-merge"* ]]
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 0 ]

  merge_commit=$(git -C memory rev-parse HEAD)
  # The authority is still the first parent (D6) and the pending commit the
  # second, so the session boundary changed nothing about what landed.
  [ "$(git -C memory rev-parse "${merge_commit}^1")" = "$live_before" ]
  [ "$(git -C memory rev-parse "${merge_commit}^2")" = "$pending" ]
  [ "$merge_commit" = "$(git -C memory rev-parse live)" ]
  git -C memory cat-file -e "$merge_commit:SYNTH.md"
  [ ! -f "$(gitlore_merge_state_file memory)" ]
  run git -C memory rev-parse -q --verify "$GITLORE_PENDING_REF"
  [ "$status" -ne 0 ]
}

@test "recovery: a merge that never started is reported, not announced as prepared" {
  # The merge's own output is discarded on purpose — a conflict is the expected
  # outcome and the conflicted worktree IS the deliverable. But a merge that
  # never started leaves no MERGE_HEAD, and without checking for it the caller
  # would write a state file and dispatch a sub-agent to resolve nothing.
  # Reproduced here with an authority HEAD already contains, which is now
  # recognized by ancestry BEFORE the detach that used to make this diagnosis
  # move HEAD — so the report names the state rather than relaying git's
  # "Already up to date" from a checkout already performed.
  before=$(git -C memory rev-parse HEAD)
  run --separate-stderr gitlore_prepare_merge memory live HEAD
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"already contains HEAD"* ]]
  run git -C memory rev-parse -q --verify MERGE_HEAD
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$before" ]
}

# --- a preparation interrupted part-way ---
#
# gitlore_prepare_merge moves HEAD, then merges. A caller killed anywhere inside
# it (the tool timeout that killed a push-memory.sh run mid-merge) must leave
# something every gate can see, so the state file is written BEFORE the
# preparation starts and completed after it: each window then sorts into the
# classifier the checkout-cleared cases already run through.

@test "recovery: the state file is written before the preparation starts, and cleared when it fails" {
  make_diverged_head_vs_live memory
  yield_with_failing_prepare() {
    # Both paths below are recomputed rather than read from the test body:
    # `run` evaluates this in a context that carries neither the body's
    # variables nor its exports.
    # shellcheck disable=SC2317  # the body runs through gitlore_yield_merge
    gitlore_prepare_merge() {
      if [ -f "$(gitlore_merge_state_file memory)" ]; then
        echo present > "$BATS_TEST_TMPDIR/seen"
      else
        echo absent > "$BATS_TEST_TMPDIR/seen"
      fi
      return 1
    }
    gitlore_yield_merge memory live head-vs-live HEAD
  }
  run --separate-stderr yield_with_failing_prepare
  [ "$status" -ne 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/seen")" = "present" ]
  # A preparation that never happened leaves no state for a later gate to
  # classify — it would only find a dead merge and say so.
  [ ! -f "$(gitlore_merge_state_file memory)" ]
  run gitlore_detect_stale_merge_state memory
  [ "$output" = "clean" ]
}

@test "recovery: a preparation interrupted after its merge staged is completed by the next gate, not flagged" {
  make_diverged_head_vs_live memory
  pending=$(git -C memory rev-parse HEAD)
  statefile=$(gitlore_merge_state_file memory)
  # Killed between `git merge` and the briefing: the state file is still the
  # marker written before the preparation, with no briefing in it.
  yield_dying_before_briefing() {
    # shellcheck disable=SC2317  # the body runs through gitlore_yield_merge
    gitlore_write_merge_state() { return 1; }
    gitlore_yield_merge memory live head-vs-live HEAD
  }
  run --separate-stderr yield_dying_before_briefing
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse -q --verify MERGE_HEAD)" = "$pending" ]
  [ -f "$statefile" ]
  run jq -e 'has("changed_files")' "$statefile"
  [ "$status" -ne 0 ]

  run --separate-stderr gitlore_guard_stale_merge_state memory
  [ "$status" -ne 0 ]
  all="$output$stderr"
  [[ "$all" == *"continue-after-merge"* ]]
  [[ "$all" != *"manual intervention"* ]]
  # The briefing the merger sub-agent reads is now there, and names both sides.
  [ "$(jq -r '.source_ref' "$statefile")" = "$pending" ]
  [ "$(jq -r '.target_ref' "$statefile")" = "live" ]
  jq -e '.changed_files | index("HEAD_SIDE.md") != null and index("LIVE.md") != null' "$statefile"
  [ -f "$(jq -r '.mine_diff' "$statefile")" ]
  [ -f "$(jq -r '.theirs_diff' "$statefile")" ]
  [ -f "$(jq -r '.tree' "$statefile")" ]
  [ "$(git -C memory rev-parse -q --verify MERGE_HEAD)" = "$pending" ]
}

@test "recovery: a preparation interrupted before its merge ran is discarded, and the gate re-prepares it" {
  make_diverged_head_vs_live memory
  pending=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  # Killed between the checkout onto the authority and `git merge`: marker
  # written, pin set, HEAD on the authority, nothing merged.
  gitlore_write_merge_marker memory head-vs-live "$pending" live continue-after-merge
  git -C memory update-ref "$GITLORE_PENDING_REF" "$pending"
  git -C memory checkout -q --detach live
  run gitlore_detect_stale_merge_state memory
  [ "$output" = "stale-no-merge-head" ]

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  all="$output$stderr"
  [[ "$all" == *"interrupted before its merge ran"* ]]
  [[ "$all" == *"memory merge prepared"* ]]
  # Re-prepared from the pending commit the interruption had left behind.
  [ "$(git -C memory rev-parse -q --verify MERGE_HEAD)" = "$pending" ]
  [ "$(git -C memory rev-parse HEAD)" = "$live" ]
  jq -e 'has("changed_files")' "$(gitlore_merge_state_file memory)"
}

@test "recovery: MERGE_HEAD with no state file is a merge gitlore did not prepare, and blocks" {
  make_diverged_head_vs_live memory
  # A merge started by hand in the store. gitlore's own preparations record
  # their state file first, so no interruption of one leaves this shape.
  git -C memory merge --no-commit --no-ff live >/dev/null 2>&1 || true
  mh=$(git -C memory rev-parse -q --verify MERGE_HEAD)
  [ -n "$mh" ]
  [ ! -f "$(gitlore_merge_state_file memory)" ]

  run gitlore_detect_stale_merge_state memory
  [ "$output" = "orphaned-merge-head" ]

  run --separate-stderr gitlore_guard_stale_merge_state memory
  [ "$status" -ne 0 ]
  all="$output$stderr"
  [[ "$all" == *"did not prepare"* ]]
  [[ "$all" == *"merge --abort"* ]]
  [[ "$all" == *"$mh"* ]]
}

# --- a merge whose MERGE_HEAD a checkout cleared ---
#
# `git checkout` — including the no-op re-checkout `submodule update` runs —
# calls remove_branch_state(), which unlinks MERGE_HEAD and MERGE_MSG silently
# while leaving the staged merge result in the index. A clean auto-merge has no
# unmerged entries for checkout to refuse over, so the state file outlives its
# own discriminator. What can be recovered depends on what the store holds, and
# every branch below is decided mechanically (D7).

@test "recovery: a checkout-cleared merge that nothing landed is discarded, and the gate re-prepares it" {
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  pending=$(git -C memory rev-parse "$GITLORE_PENDING_REF")
  # The shape a hand-run `git merge --abort` leaves: the pointers go and the
  # index is reset to HEAD, so nothing of the merge survives but gitlore's own
  # files. This is what a user asking to revert to the pre-merge state gets.
  git -C memory merge --abort
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD || true)" ]

  run --separate-stderr bash "$PRE_COMMIT"
  all="$output$stderr"
  # It says what it disposed of before it re-prepares, so a repair is never a
  # silent rewrite of the store.
  [[ "$all" == *"nothing landed"* ]]
  [[ "$all" == *"leftover state is discarded"* ]]
  [[ "$all" == *"memory merge prepared"* ]]
  # The divergent commit is not orphaned by the disposal: the merge the gate
  # just prepared is the same one, against the same pending side.
  [ "$(jq -r .source_ref "$(gitlore_merge_state_file memory)")" = "$pending" ]
}

@test "recovery: /gitlore:resolve repairs a checkout-cleared merge instead of refusing over it" {
  # The skill's own script walks the same guard every gate does, so a state it
  # could not touch made the documented repair path the one place a user could
  # not be sent. Push live first, or the default mode takes its "remote has no
  # live branch" early return before reaching the guard.
  git -C memory push -q origin live
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  git -C memory merge --abort

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  # Reaching the divergence again IS the repair: the script gets past the stale
  # state and prepares the merge the store still needs.
  [[ "$output$stderr" == *"memory merge prepared"* ]]
}

@test "recovery: a checkout-cleared merge with its synthesis staged keeps it and asks for the sub-agent" {
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  pending=$(git -C memory rev-parse "$GITLORE_PENDING_REF")
  # The merger sub-agent's synthesis, staged exactly as it leaves it.
  echo "synthesized" > memory/SYNTH.md
  git -C memory add -A
  git -C memory checkout -q --detach HEAD
  [ -z "$(git -C memory rev-parse -q --verify MERGE_HEAD || true)" ]

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [ "$(git -C memory rev-parse -q --verify MERGE_HEAD)" = "$pending" ]
  [ -f "$(git -C memory rev-parse --git-path MERGE_MSG)" ]
  [[ "$all" == *"memory merge prepared"* ]]
  [[ "$all" == *"continue-after-merge"* ]]
  # The staged synthesis survives: nothing aborted the merge out from under it.
  run git -C memory diff --cached --name-only
  [[ "$output" == *"SYNTH.md"* ]]
}

@test "recovery: a merge that landed before the checkout is restored, not declared dead" {
  make_diverged_head_vs_live memory
  bash "$PRE_COMMIT" || true
  # Land the merge as the continuation does, then let a checkout move HEAD off
  # it while the state file is still there.
  GITLORE_MEMORY_COMMIT=1 git -C memory commit -q --no-edit
  landed=$(git -C memory rev-parse HEAD)
  git -C memory checkout -q --detach live
  # The merge commit is reachable from no ref, and `fsck --unreachable` still
  # does not name it — reflog entries are reachability roots — so "is there an
  # unreachable commit" is the wrong question to ask about a landed merge.
  run git -C memory fsck --unreachable
  [[ "$output" != *"$landed"* ]]

  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"$landed"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$landed" ]
  [ "$(git -C memory rev-parse live)" = "$landed" ]
  [ ! -f "$(gitlore_merge_state_file memory)" ]
  run git -C memory rev-parse -q --verify "$GITLORE_PENDING_REF"
  [ "$status" -ne 0 ]
}

# --- Item 1.3 slice 1: gitlore_recover_landed_merge stages the gitlink it
# moved, in the store that recorded it, so a memory commit right after does not
# meet the pin guard on a tier gitlore itself just left ahead. ---
#
# Both rc-0 branches leave the STORE's own gitdir clean (its own MERGE_HEAD and
# merge-state file are gone), but neither touches the ENCLOSING store's index —
# so a tier recovered this way looks, to the pin guard, exactly like one moved
# off its pin by hand. Every fixture below diverges a tier from its own `live`
# and prepares the merge through the real hook — precedent:
# tests/tier_divergence.bats "pre-commit prepares a merge when a tier commit
# diverged from its own live" — then lands it with a bare `git commit --no-edit`
# rather than through /gitlore:merge's own continuation, which is what leaves
# the moved gitlink unstaged in memory's index (D43 only covers the normal
# advancing path).
tier_prepare_head_vs_live() {
  local tier="${1:-ddaanet}"
  make_tier_in_memory "$tier"
  set_tier_manifest "$tier"
  git -C "memory/$tier" fetch -q origin "live:live"
  git -C "memory/$tier" checkout -q --detach live
  advance_branch_with_file "memory/$tier" live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> "memory/$tier/MEMORY.md"
  printf 'memory: record the org fact\n' > "$(gitlore_commit_msg_file memory)"
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  [ -n "$(git -C "memory/$tier" rev-parse -q --verify MERGE_HEAD)" ]
}

@test "recovery: a landed tier merge stages the moved gitlink in the memory store's index" {
  tier_prepare_head_vs_live ddaanet
  pin_before=$(git -C memory rev-parse ":ddaanet")

  # Land directly, bypassing the continuation: MERGE_HEAD clears (git's own
  # post-commit cleanup), the merge-state file does not, and memory's index is
  # still pinned at the pre-merge commit.
  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$landed" != "$pin_before" ]
  # HEAD moves off the landed merge onto a clean ancestor of it — the branch
  # that has to check out the merge again before it can stage anything.
  git -C memory/ddaanet checkout -q --detach live
  # An unapproved edit sitting in the memory worktree while the recovery runs.
  printf 'unapproved\n' > memory/SCRATCH.md

  run --separate-stderr gitlore_guard_stale_merge_state memory/ddaanet
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]
  # The gitlink it moved, and nothing else: `add -- <tier>`, never `add -A`.
  # An over-broad stage here would put unapproved content into the index the
  # next approved memory commit sweeps up. After the pin assertion, so the case
  # still reds on the pin against unchanged code.
  staged_in_memory=$(git -C memory diff --cached --name-only)
  [[ "$staged_in_memory" != *SCRATCH.md* ]]
}

@test "recovery: the branch where HEAD already carries the landed merge stages it too" {
  tier_prepare_head_vs_live ddaanet

  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit
  landed=$(git -C memory/ddaanet rev-parse HEAD)
  # HEAD is left exactly where the commit put it — the OTHER rc-0 branch from
  # the case above, where only the bookkeeping outlived the merge.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$landed" ]

  run --separate-stderr gitlore_guard_stale_merge_state memory/ddaanet
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]
}

# A continuation killed right after its own bookkeeping commit, then re-run.
# The pair is already adopted — memory's index already records the tier's
# HEAD — and the tier's merge-state file is left in place (that commit clears
# only the tier's own MERGE_HEAD, never memory's leftover state), so the next
# gate still classifies this as a landed merge to recover. Without the
# short-circuit, gitlore_adopt_recovered_merge composes up again and projects
# the carrier's text over the root-index edit made since.
@test "recovery: adoption is a no-op when the enclosing index already records the tier's HEAD" {
  tier_prepare_head_vs_live ddaanet

  GITLORE_MEMORY_COMMIT=1 git -C memory/ddaanet commit -q --no-edit
  landed=$(git -C memory/ddaanet rev-parse HEAD)

  # Adopt once, directly, and commit it in memory — exactly what a
  # continuation's own tail does. Calling the adoption directly, rather than
  # through gitlore_recover_landed_merge, leaves the tier's merge-state file
  # untouched for the recovery call below to still find.
  abs=$(cd memory/ddaanet && pwd)
  gitlore_adopt_recovered_merge memory/ddaanet "$abs"
  commit_memory_state "memory: adopt the tier merge"
  [ "$(git -C memory rev-parse ":ddaanet")" = "$landed" ]

  # A root-index edit to that tier's own line, made after the pair was
  # adopted — the edit a second up projection would overwrite.
  awk '/^- \[org fact\]/ { sub(/ — .*/, " — edited after adoption"); } { print }' \
    memory/MEMORY.md > "$BATS_TEST_TMPDIR/edited-index"
  cp "$BATS_TEST_TMPDIR/edited-index" memory/MEMORY.md
  grep -qxF -- "- [org fact](ddaanet/f.md) — edited after adoption" memory/MEMORY.md

  run --separate-stderr gitlore_guard_stale_merge_state memory/ddaanet
  [ "$status" -eq 0 ]
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/edited-index"
  git -C memory diff --cached --quiet
}

# BORN-GREEN, unlike the four cases around it. `--show-superproject-working-tree`
# does not by itself distinguish a tier (superproject = an enclosing memory
# store) from the memory root (superproject = the user's own project, which is
# never a memory store just for having one) — so staging must be scoped by an
# explicit predicate: the superproject carries MEMORY.md at its root AND the
# recovered store's own path, relative to that superproject, is NOT the
# superproject's own `submodule.gitlore-memory.path` (both conditions — no
# membership test against `gitlore_tier_paths`, which would only restate what
# `--show-superproject-working-tree` already settled). Staging the memory
# root's own gitlink into the user's project index is the pre-commit hook's job,
# gated by FR11's approval — not this recovery's to do unprompted.
#
# "Nothing staged in the parent repo" held against the code as it stood when
# this case was written, so it characterizes the scope rule rather than proving
# it on its own. Its discriminating proof is the memory-root exclusion clause,
# and the case that isolates that clause is the host-project one below: drop the
# exclusion and THAT case reds, while this one does not.
#
# It no longer reds under a predicate missing the exclusion clause either:
# adoption stages the pair, so a parent with no root MEMORY.md fails
# `add -- MEMORY.md memory` on the pathspec and stages nothing — this case then
# passes for the wrong reason. Read it as a characterization of the memory
# root's scope, not as the clause's pin.
@test "recovery: the same recovery for the memory root stages nothing in the parent repo" {
  make_diverged_head_vs_live memory
  run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]

  GITLORE_MEMORY_COMMIT=1 git -C memory commit -q --no-edit
  landed=$(git -C memory rev-parse HEAD)
  git -C memory checkout -q --detach live

  before=$(git diff --cached --name-only)
  run --separate-stderr gitlore_guard_stale_merge_state memory
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$landed" ]
  [ "$(git diff --cached --name-only)" = "$before" ]
}

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
