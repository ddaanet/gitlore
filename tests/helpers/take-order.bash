#!/usr/bin/env bash
# Fixtures for the take-order suites: a published memory store with mounted
# tiers, and the upstream and local moves a /gitlore:merge run has to meet.
# Needs helpers/setup, fixtures, tier-fixtures, merge-memory and stub-synth.

# A memory store published on MEMORY_REMOTE with one tier per argument, each
# carrying one fact, composed into root, committed and recorded by the parent —
# the state every take starts from. Each tier is detached at its local `live`,
# which equals its remote's `live`, and the memory store's `live` equals HEAD.
# Args: tier names (default "ddaanet").
take_base_store() {
  local tier
  [ "$#" -gt 0 ] || set -- ddaanet
  wire_memory_remote
  for tier in "$@"; do
    mount_tier_at_live "$tier"
  done
  set_tier_manifest "$@"
  for tier in "$@"; do
    seed_tier_bullet "$tier" shared.md "a portable fact"
    git -C "memory/$tier" add -A
    git -C "memory/$tier" commit -qm "seed $tier"
    git -C "memory/$tier" push -q . HEAD:refs/heads/live
    git -C "memory/$tier" push -q origin live
  done
  # The pin guard compares each tier with the gitlink the index records.
  git -C memory add -- "$@"
  gitlore_compose memory
  commit_memory_state
  git -C memory push -q . HEAD:refs/heads/live
  git -C memory push -q origin live
}

# Publish a memory commit that records tier $1 at commit $2 and carries root
# line $3, on top of the memory remote's `live`. The sha goes to stdout.
memory_remote_records() {
  local tier="$1" sha="$2" line="$3" work out
  work="$(mktemp -d "$TMP_REPO/mwork.XXXXXX")"
  git clone -q -b live "$MEMORY_REMOTE" "$work"
  (
    cd "$work" || exit 1
    git config user.email "other@example.com"
    git config user.name "Other"
    git update-index --cacheinfo "160000,$sha,$tier"
    printf '%s\n' "$line" >> MEMORY.md
    git add MEMORY.md
    git commit -qm "other checkout records $tier"
    git push -q origin live
  )
  out=$(git -C "$work" rev-parse HEAD)
  rm -rf "$work"
  printf '%s\n' "$out"
}

# Commit a fact in tier $1 (file $2), then record it locally: the carrier's line
# in root, the new gitlink, one memory commit with `live` following. Unpublished.
local_tier_commit_recorded() {
  local tier="$1" file="$2"
  seed_tier_bullet "$tier" "$file" "committed here"
  git -C "memory/$tier" add -A
  git -C "memory/$tier" commit -qm "local tier fact $file"
  git -C "memory/$tier" push -q . HEAD:refs/heads/live
  seed_root_bullet "$tier/$file" "committed here"
  git -C memory add -A
  git -C memory commit -qm "record $tier fact $file"
  git -C memory push -q . HEAD:refs/heads/live
}

# The upstream half of a pin move: tier $1 gains a commit on its remote and the
# memory remote records it. Echoes the tier commit's sha.
upstream_moves_pin() {
  local tier="$1" file="$2" sha
  sha=$(push_tier_fact "$tier" "- [${file%.md}](${file}) — from upstream")
  memory_remote_records "$tier" "$sha" "- [${file%.md}]($tier/${file}) — from upstream" >/dev/null
  printf '%s\n' "$sha"
}

# Publish to tier $1's remote a commit whose carrier line welds two bullets and
# whose tree holds the file the second names, which is what the arrival repair
# splits on. Echoes the commit's sha.
push_tier_weld() {
  local tier="$1" work out
  work="$(mktemp -d "$TMP_REPO/twork.XXXXXX")"
  git clone -q "$TMP_REPO/.bare-$tier.git" "$work"
  (
    cd "$work" || exit 1
    git config user.email "other@example.com"
    git config user.name "Other"
    git checkout -q -B live origin/live
    printf -- '- [A](welded_a.md) — a- [B](welded_b.md) — b\n' >> MEMORY.md
    printf 'body\n' > welded_b.md
    git add -A
    git commit -qm "welded arrival"
    git push -q origin live
  )
  out=$(git -C "$work" rev-parse HEAD)
  rm -rf "$work"
  printf '%s\n' "$out"
}

# A commit on top of tier $1's remote `live`, built in a scratch clone and never
# pushed, so no repository but the scratch clone holds it. Echoes its sha.
unpublished_tier_commit() {
  local tier="$1" work out
  work="$(mktemp -d "$TMP_REPO/twork.XXXXXX")"
  git clone -q "$TMP_REPO/.bare-$tier.git" "$work"
  (
    cd "$work" || exit 1
    git config user.email "other@example.com"
    git config user.name "Other"
    git checkout -q -B live origin/live
    printf -- '- [lost](lost.md) — held by one checkout only\n' >> MEMORY.md
    git commit -qam "never pushed"
  )
  out=$(git -C "$work" rev-parse HEAD)
  rm -rf "$work"
  printf '%s\n' "$out"
}

# A commit on tier $1's remote branch `side`, which `live` does not contain,
# fetched into the mounted tier as well. Echoes its sha.
side_branch_tier_commit() {
  local tier="$1" work out
  work="$(mktemp -d "$TMP_REPO/twork.XXXXXX")"
  git clone -q "$TMP_REPO/.bare-$tier.git" "$work"
  (
    cd "$work" || exit 1
    git config user.email "other@example.com"
    git config user.name "Other"
    git checkout -q -B side origin/live
    printf -- '- [side](side.md) — on a branch live never took\n' >> MEMORY.md
    git commit -qam "side branch fact"
    git push -q origin side
  )
  out=$(git -C "$work" rev-parse HEAD)
  rm -rf "$work"
  git -C "memory/$tier" fetch -q origin side
  printf '%s\n' "$out"
}

# The path of the merge state file of store $1, whether or not it exists.
store_state_file() {
  printf '%s/gitlore-merge-state\n' "$(git -C "$1" rev-parse --absolute-git-dir)"
}

# Run the take; while it yields a prepared merge, record, once the take has
# exited with its state file written, which store the file belongs to, what the
# store's index holds unmerged and what the file lists as conflicted, land the
# merge with the stub merger, and take again.
# Leaves, one line per yield in TAKE_YIELDS: "<store> unmerged=<paths>
# conflicted=<paths>", each <paths> the comma-joined list ("" when none), and in
# TAKE_STATUS the status of the last take. A yield of memory also records
# " gitlink=<sha>:<tier HEAD sha>" for the first tier among the arguments: the
# commit memory's index holds for it at stage 0 (empty while it is unmerged), and
# the commit the tier sits at.
# Args: the tier stores (memory/<tier>) whose state file to look for besides
# memory's own.
# shellcheck disable=SC2034  # TAKE_YIELDS and TAKE_STATUS are read by the callers
drive_take_to_rest() {
  local store n=0 rc found paths conflicted line
  TAKE_YIELDS=()
  while [ "$n" -lt 6 ]; do
    n=$((n + 1))
    rc=0
    bash "$CMD" >"$BATS_TEST_TMPDIR/take.$n.out" 2>"$BATS_TEST_TMPDIR/take.$n.err" || rc=$?
    TAKE_STATUS=$rc
    [ "$rc" -ne 0 ] || return 0
    found=""
    for store in memory "$@"; do
      [ -f "$(store_state_file "$store")" ] || continue
      found="$store"
      paths=$(git -C "$store" diff --name-only --diff-filter=U | paste -sd, -)
      conflicted=$(jq -r '.conflicted_files[]?' "$(store_state_file "$store")" | paste -sd, -)
      line="$store unmerged=$paths conflicted=$conflicted"
      if [ "$store" = memory ] && [ "$#" -gt 0 ]; then
        line="$line gitlink=$(git -C memory ls-files -s -- "${1#memory/}" | awk '$3 == 0 { print $2 }'):$(git -C "$1" rev-parse HEAD)"
      fi
      TAKE_YIELDS+=("$line")
      break
    done
    [ -n "$found" ] || return 0
    run_stub_synth "$found" >>"$BATS_TEST_TMPDIR/take.$n.out" 2>>"$BATS_TEST_TMPDIR/take.$n.err" || return 1
  done
}

# Fork memory's HEAD from its local `live`: `live` takes the memory remote's
# `live` (which a fixture has already made record something), and HEAD gains a
# root-only commit that `live` lacks, so neither contains the other.
fork_root_from_live() {
  git -C memory fetch -q --no-recurse-submodules origin live
  git -C memory push -q . origin/live:refs/heads/live
  printf 'local only\n' > memory/local-only.md
  git -C memory add local-only.md
  git -C memory commit -qm "a root-only fact on HEAD"
}

# Every yield of memory's own merge in TAKE_YIELDS (drive_take_to_rest given the
# tier) holds tier HEAD $1 both in memory's index and in the tier: the tier was
# taken before the merge was prepared. At least one such yield must exist.
assert_root_yields_at_tier_head() {
  local want="$1" y n=0
  for y in "${TAKE_YIELDS[@]}"; do
    [[ "$y" == "memory "* ]] || continue
    n=$((n + 1))
    [[ "$y" == *"gitlink=$want:$want" ]] || { printf 'yield: %s\nwant the index gitlink and the tier HEAD both %s\n' "$y" "$want" >&2; return 1; }
  done
  [ "$n" -ge 1 ] || { printf 'memory never yielded a merge: %s\n' "${TAKE_YIELDS[*]-}" >&2; return 1; }
}
