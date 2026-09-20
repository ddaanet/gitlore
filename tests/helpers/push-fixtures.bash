#!/usr/bin/env bash
# Shared setup and fixtures for the push_behind_vs_diverged / push_tier_publication*
# suites (/gitlore:push).

# shellcheck disable=SC2034   # used by callers' @test bodies
CMD="$PLUGIN_ROOT/scripts/push-memory.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
}
teardown() { teardown_tmp_repo; }

publish_memory() {
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

# A tier in the state SessionStart leaves it in: local `live` created from the
# remote, worktree detached at `live`.
mount_tier_at_live() {
  local tier="${1:-ddaanet}"
  make_tier_in_memory "$tier"
  git -C "memory/$tier" fetch -q origin "live:live"
  git -C "memory/$tier" checkout -q --detach live
}

# Advance a tier past its own remote with a plain commit that adds no index
# line — the ordinary shape of a local advance, before the push that would
# publish it. Leaves both HEAD and local `live` on the new commit (not
# stranded — `strand_live_ahead_of_pin` is the fixture for that shape).
# Args: $1 = tier, $2 = file (default "plain.md").
advance_tier_past_remote() {
  local tier="$1" file="${2:-plain.md}"
  printf 'x\n' > "memory/$tier/$file" || return 1
  git -C "memory/$tier" add "$file" || return 1
  GITLORE_MEMORY_COMMIT=1 git -C "memory/$tier" commit -q -m "plain commit, no index line" || return 1
  git -C "memory/$tier" branch -f live HEAD
}

# Build a commit as a child of $2, in a scratch clone of the tier's own local
# repo (so an ancestor never pushed to the tier's remote is still reachable),
# and push it to $3 on the tier's bare remote — a side ref, not `live`: the
# remote's `live` only moves once the hook below fires on its next receive.
# Echoes the new commit's sha. Args: $1 = tier, $2 = parent sha, $3 = ref,
# $4 = line appended to MEMORY.md.
push_side_ref_child() {
  local tier="$1" parent="$2" refname="$3" line="$4" work
  local bare="$TMP_REPO/.bare-$tier.git"
  work="$(mktemp -d "$BATS_TEST_TMPDIR/tier-work.XXXXXX")" || return 1
  git clone -q "memory/$tier" "$work" || return 1
  git -C "$work" config user.email "test@example.com" || return 1
  git -C "$work" config user.name "Test" || return 1
  git -C "$work" checkout -q --detach "$parent" || return 1
  printf '%s\n' "$line" >> "$work/MEMORY.md" || return 1
  git -C "$work" commit -aqm "duplicate arrival" || return 1
  git -C "$work" push -q "$bare" "HEAD:$refname" || return 1
  git -C "$work" rev-parse HEAD
}

# A one-shot post-receive hook on a tier's bare remote: on the next push it
# receives, it snaps `live` onto $2 and removes itself — the idiom
# half_landed_tier_fixture uses for a lock, here for a ref. Args: $1 = tier,
# $2 = the sha `live` lands on.
move_tier_remote_live_on_next_push() {
  local tier="$1" target="$2"
  local hook="$TMP_REPO/.bare-$tier.git/hooks/post-receive"
  # shellcheck disable=SC2016  # $0 is the generated hook's own, not this shell's
  printf '#!/bin/sh\ngit update-ref refs/heads/live %s\nrm -f "$0"\n' "$target" > "$hook" || return 1
  chmod +x "$hook"
}

# Shared shape for both variants below: two tiers, `aa` mounted before `bb`
# (their `.gitmodules` order, which the tier loop and the take pass both
# read). `aa`'s own loop iteration publishes P; a post-receive hook then snaps
# its remote's `live` onto D — a child of P carrying a duplicate bullet twice
# (the arrival shape "a repair taken by the behind arm is published before
# memory records it" repairs) — behind the push's back. Whatever the
# variant does with `bb` next runs the take pass over every tier, `aa`
# included: it fast-forwards `aa` onto D and repairs the duplicate into a new
# commit entirely inside `aa`'s local `live` — `aa`'s own loop iteration
# already ran and does not come back around to publish it.
# Called directly, never in `$(...)`, so errexit covers every step. Sets $P, $D.
setup_repair_race_on_aa() {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  mount_tier_at_live aa
  mount_tier_at_live bb
  set_tier_manifest aa bb
  gitlore_compose memory
  commit_memory_state
  git -C memory push -q . HEAD:refs/heads/live
  publish_memory

  advance_tier_past_remote aa
  commit_memory_state
  git -C memory push -q . HEAD:refs/heads/live
  P=$(git -C memory/aa rev-parse HEAD)
  [ "$(git -C memory rev-parse live:aa)" = "$P" ]
  [ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse live)" != "$P" ]

  D=$(push_side_ref_child aa "$P" refs/heads/stash-d \
    "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")
  [ "$(git --git-dir="$TMP_REPO/.bare-aa.git" rev-parse stash-d)" = "$D" ]
  move_tier_remote_live_on_next_push aa "$D"
}

# `aa`'s local `live` is a repair of $1: a commit whose only parent is $1 and
# whose MEMORY.md carries the duplicated bullet once. Sets $aa_live.
assert_aa_live_repairs() {
  aa_live=$(git -C memory/aa rev-parse live)
  [ "$(git -C memory/aa rev-list --parents -n 1 "$aa_live")" = "$aa_live $1" ]
  [ "$(git -C memory/aa show "$aa_live:MEMORY.md" | grep -cF -- '- [A](a.md) — x')" -eq 1 ]
}
