#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order

# A take visits every mounted tier first and the memory root last, and writes
# root's index once, at the end, in one bookkeeping commit naming the tiers it
# moved. Root-first existed only so that a per-tier bookkeeping commit did not
# meet upstream root's equivalent commit as a divergence.

@test "a take that moves two tiers reports both tiers before it reports memory" {
  take_base_store alpha beta
  push_tier_fact alpha '- [a-up](a-up.md) — published upstream' >/dev/null
  push_tier_fact beta '- [b-up](b-up.md) — published upstream' >/dev/null

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  alpha_at=$(printf '%s\n' "$output" | grep -n "tier 'alpha'" | head -n 1 | cut -d: -f1)
  beta_at=$(printf '%s\n' "$output" | grep -n "tier 'beta'" | head -n 1 | cut -d: -f1)
  # The memory root's own report: its fast-forward or its nothing-to-take line,
  # not the bookkeeping line that names a tier.
  memory_at=$(printf '%s\n' "$output" | grep -nE '^gitlore: memory — (already holds|fast-forwarded)' | head -n 1 | cut -d: -f1)
  [ -n "$alpha_at" ]
  [ -n "$beta_at" ]
  [ -n "$memory_at" ]
  [ "$alpha_at" -lt "$memory_at" ] || { printf 'alpha at line %s, memory at line %s\n' "$alpha_at" "$memory_at" >&2; return 1; }
  [ "$beta_at" -lt "$memory_at" ] || { printf 'beta at line %s, memory at line %s\n' "$beta_at" "$memory_at" >&2; return 1; }
}

@test "a take that moves two tiers records them in one bookkeeping commit naming both" {
  take_base_store alpha beta
  before=$(git -C memory rev-parse HEAD)
  push_tier_fact alpha '- [a-up](a-up.md) — published upstream' >/dev/null
  push_tier_fact beta '- [b-up](b-up.md) — published upstream' >/dev/null

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  count=$(git -C memory rev-list --count "$before..HEAD")
  [ "$count" -eq 1 ] || { printf 'bookkeeping commits: %s, want 1\n' "$count" >&2; return 1; }
  msg=$(git -C memory log -1 --format=%B)
  [[ "$msg" == *alpha* ]]
  [[ "$msg" == *beta* ]]
  # What the one commit records: both moves, and root's lines for both.
  [ "$(git -C memory rev-parse HEAD:alpha)" = "$(git -C memory/alpha rev-parse HEAD)" ]
  [ "$(git -C memory rev-parse HEAD:beta)" = "$(git -C memory/beta rev-parse HEAD)" ]
  git -C memory show HEAD:MEMORY.md | grep -qF -- '- [a-up](alpha/a-up.md) — published upstream'
  git -C memory show HEAD:MEMORY.md | grep -qF -- '- [b-up](beta/b-up.md) — published upstream'
  [ -z "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse live)" = "$(git -C memory rev-parse HEAD)" ]
}

@test "a root remote commit that already records the tier move leaves no bookkeeping commit to write" {
  # Passes with root first as well: a pin that must stay true after the reorder.
  take_base_store alpha
  before=$(git -C memory rev-parse HEAD)
  tier_sha=$(upstream_moves_pin alpha a-up.md)
  remote_head=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$tier_sha" ]
  [ "$(git -C memory rev-parse HEAD:alpha)" = "$tier_sha" ]
  # Root took the one upstream commit, which already records the pin and the
  # line: nothing is left for a bookkeeping commit to record.
  [ "$(git -C memory rev-parse HEAD)" = "$remote_head" ]
  [ "$(git -C memory rev-list --count "$before..HEAD")" -eq 1 ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a welded line in one tier's arrival is repaired in the tier and root records the repaired tier" {
  # D52 pin: the arrival repair runs per tier, ahead of anything root records.
  # Holds with root first as well, so it passes before the take order moves.
  take_base_store alpha beta
  push_tier_fact beta '- [b-up](b-up.md) — published upstream' >/dev/null
  welded=$(push_tier_weld alpha)
  # Premise: the arrival really carries the weld, unsplit.
  git --git-dir="$TMP_REPO/.bare-alpha.git" show "$welded:MEMORY.md" | grep -qxF -- '- [A](welded_a.md) — a- [B](welded_b.md) — b'

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/alpha rev-list --parents -n 1 HEAD)" = "$(git -C memory/alpha rev-parse HEAD) $welded" ]
  [ "$(git -C memory/alpha log -1 --format=%s)" = "Repair the MEMORY.md structure alpha received" ]
  [ "$(git -C memory/alpha rev-parse live)" = "$(git -C memory/alpha rev-parse HEAD)" ]
  [ "$(git -C memory rev-parse HEAD:alpha)" = "$(git -C memory/alpha rev-parse HEAD)" ]
  [ "$(git -C memory rev-parse HEAD:beta)" = "$(git -C memory/beta rev-parse HEAD)" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a dirty tier is refused before root moves and the printed remedy is to commit first" {
  take_base_store ddaanet
  upstream_moves_pin ddaanet up.md >/dev/null
  seed_tier_bullet ddaanet mine.md "an uncommitted fact"
  root_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  tier_before=$(git -C memory/ddaanet rev-parse HEAD)
  index_before=$(cat memory/MEMORY.md)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"tier 'ddaanet'"* ]]
  # The remedy is to commit first; "uncommitted" alone does not satisfy this.
  [[ "$stderr" == *[Cc]ommit\ * ]]
  # Nothing moved: not the tier, not root's HEAD or `live`, not root's index.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$root_before" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
  [ "$(cat memory/MEMORY.md)" = "$index_before" ]
}

@test "a pin only upstream moved is taken in one loop: root merge takes the gitlink, tier fast-forwards" {
  take_base_store ddaanet
  # A root commit of this checkout's own, unpublished, so root really merges.
  printf 'local only\n' > memory/local-only.md
  git -C memory add -A
  git -C memory commit -qm "a root-only fact"
  git -C memory push -q . HEAD:refs/heads/live
  tier_sha=$(upstream_moves_pin ddaanet up.md)

  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ]
  # One yield: root's merge. The tier fast-forwarded and had nothing to merge.
  [ "${#TAKE_YIELDS[@]}" -eq 1 ] || { printf '%s\n' "${TAKE_YIELDS[@]}" >&2; return 1; }
  [[ "${TAKE_YIELDS[0]}" == "memory unmerged= "* ]] || { printf '%s\n' "${TAKE_YIELDS[0]}" >&2; return 1; }
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$tier_sha" ]
  grep -qF -- '- [up](ddaanet/up.md) — from upstream' memory/MEMORY.md
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a dirty second tier is refused before the first tier moves" {
  take_base_store alpha beta
  push_tier_fact alpha '- [a-up](a-up.md) — published upstream' >/dev/null
  push_tier_fact beta '- [b-up](b-up.md) — published upstream' >/dev/null
  seed_tier_bullet beta mine.md "an uncommitted fact"
  a=$(git -C memory/alpha rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$a" ]
}

@test "a dirty tier with nothing to take does not refuse the run and the other tier is taken" {
  take_base_store alpha beta
  up=$(push_tier_fact alpha '- [a-up](a-up.md) — published upstream')
  seed_tier_bullet beta mine.md "an uncommitted fact"
  b=$(git -C memory/beta rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"uncommitted changes"* ]]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$up" ]
  [ "$(git -C memory rev-parse HEAD:alpha)" = "$up" ]
  # The dirty tier is untouched and its work is still there.
  [ "$(git -C memory/beta rev-parse HEAD)" = "$b" ]
  [ -f memory/beta/mine.md ]
}

@test "a yield on the second tier leaves root unwritten, the first tier already taken" {
  take_base_store alpha beta
  push_tier_fact alpha '- [a-up](a-up.md) — published upstream' >/dev/null
  local_tier_commit_recorded beta local.md
  push_tier_fact beta '- [b-up](b-up.md) — published upstream' >/dev/null
  root=$(git -C memory rev-parse HEAD)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/before"
  a=$(git -C memory/alpha rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [ -f "$(store_state_file memory/beta)" ]
  [ "$(git -C memory/alpha rev-parse HEAD)" != "$a" ]
  # Root's HEAD, bytes and staged set are as the take found them.
  [ "$(git -C memory rev-parse HEAD)" = "$root" ]
  cmp -- "$BATS_TEST_TMPDIR/before" memory/MEMORY.md
  [ -z "$(git -C memory diff --cached --name-only)" ]
}

@test "the bookkeeping commit names the tier it moved and not the one it did not" {
  take_base_store alpha beta
  push_tier_fact alpha '- [a-up](a-up.md) — published upstream' >/dev/null

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  msg=$(git -C memory log -1 --format=%B)
  [[ "$msg" == *alpha* ]]
  [[ "$msg" != *beta* ]]
}
