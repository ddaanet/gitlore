#!/usr/bin/env bats
# The end-of-run compose-up is a three-way gitlore_index_merge per tier: base =
# the carrier at the gitlink root's HEAD records, ours = root's block for the
# tier, theirs = the tier's carrier at its HEAD. A line only the tier changed
# is adopted, a line only root changed stands, and a line both changed apart
# carries a diff3 chunk and commits nothing. A root merge ends in the memory
# merge's continuation, which recomposes before its commit, while HEAD still
# records OURS; after that commit the staged tier HEAD reads as the pin and the
# tier's lines would be adopted by nothing.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order

# --- fixtures -----------------------------------------------------------------

# Replace text $2 by $3 in the line root's index carries, then commit root with
# `live` following. The tier is not touched.
reword_root_and_commit() {
  local content
  content=$(cat memory/MEMORY.md)
  content=${content//"$1"/"$2"}
  printf '%s\n' "$content" > memory/MEMORY.md
  grep -qF -- "$2" memory/MEMORY.md || return 1
  git -C memory add -A
  git -C memory commit -qm "root rewords a tier line"
  git -C memory push -q . HEAD:refs/heads/live
}

# Publish to tier $1's remote a commit that replaces text $2 by $3 in its
# carrier and, when $4 is given, appends it as a line. Echoes the commit's sha.
push_tier_carrier_edit() {
  local tier="$1" old="$2" new="$3" append="${4-}" work out content
  work="$(mktemp -d "$TMP_REPO/twork.XXXXXX")"
  git clone -q "$TMP_REPO/.bare-$tier.git" "$work"
  (
    cd "$work" || exit 1
    git config user.email "other@example.com"
    git config user.name "Other"
    git checkout -q -B live origin/live
    content=$(cat MEMORY.md)
    content=${content//"$old"/"$new"}
    printf '%s\n' "$content" > MEMORY.md
    [ -z "$append" ] || printf '%s\n' "$append" >> MEMORY.md
    git commit -qam "tier edits its carrier"
    git push -q origin live
  )
  out=$(git -C "$work" rev-parse HEAD)
  rm -rf "$work"
  printf '%s\n' "$out"
}

SHARED_ROOT='- [shared](ddaanet/shared.md) — a portable fact'
TF_CARRIER='- [tf](tf.md) — tier fact'
TF_ROOT='- [tf](ddaanet/tf.md) — tier fact'

# --- one tier moved, root and tier edit different lines -----------------------

@test "passing pin: a line only the tier changed and a line only the tier added are adopted into root, in one bookkeeping commit" {
  take_base_store
  before=$(git -C memory rev-parse HEAD)
  tier_sha=$(push_tier_carrier_edit ddaanet 'a portable fact' 'reworded by the tier' "$TF_CARRIER")

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  grep -qxF -- '- [shared](ddaanet/shared.md) — reworded by the tier' memory/MEMORY.md
  grep -qxF -- "$TF_ROOT" memory/MEMORY.md
  [ "$(git -C memory rev-list --count "$before..HEAD")" = "1" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$tier_sha" ]
}

@test "a line only root changed stands when the take adopts the tier's other line" {
  # The overwrite compose writes the carrier's text over root's block, so the
  # reword root committed is replaced by the base text the carrier still holds.
  take_base_store
  reword_root_and_commit 'a portable fact' 'reworded in root'
  push_tier_fact ddaanet "$TF_CARRIER" >/dev/null

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  grep -qxF -- "$TF_ROOT" memory/MEMORY.md
  grep -qxF -- '- [shared](ddaanet/shared.md) — reworded in root' memory/MEMORY.md || {
    printf 'root lost its own reword; the line reads:\n%s\n' "$(grep -F 'shared.md' memory/MEMORY.md)" >&2
    return 1
  }
}

@test "a line only root added stands when the take adopts the tier's new line" {
  take_base_store
  seed_root_bullet "ddaanet/rootonly.md" "added in root alone"
  git -C memory add -A
  git -C memory commit -qm "root adds a tier line"
  git -C memory push -q . HEAD:refs/heads/live
  push_tier_fact ddaanet "$TF_CARRIER" >/dev/null

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  grep -qxF -- "$TF_ROOT" memory/MEMORY.md
  grep -qxF -- '- [rootonly](ddaanet/rootonly.md) — added in root alone' memory/MEMORY.md || {
    echo "root's own line for the tier was dropped by the compose" >&2
    return 1
  }
}

@test "passing pin: a tier left on its pin keeps root's own text while another tier is adopted" {
  take_base_store alpha beta
  reword_root_and_commit '- [shared](beta/shared.md) — a portable fact' '- [shared](beta/shared.md) — beta reworded in root'
  push_tier_fact alpha "$TF_CARRIER" >/dev/null

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  grep -qxF -- '- [tf](alpha/tf.md) — tier fact' memory/MEMORY.md
  grep -qxF -- '- [shared](beta/shared.md) — beta reworded in root' memory/MEMORY.md
}

# --- one line both sides changed apart ----------------------------------------

# Root and the tier reword the one shared line differently, and the tier adds a
# line besides. Leaves the take's output in $output and $stderr, its tier commit
# in $tier_sha, the pin it started from in $old_pin and root's HEAD in $root_head.
both_reword_the_same_line() {
  take_base_store
  old_pin=$(git -C memory rev-parse :ddaanet)
  reword_root_and_commit 'a portable fact' 'reworded in root'
  root_head=$(git -C memory rev-parse HEAD)
  tier_sha=$(push_tier_carrier_edit ddaanet 'a portable fact' 'reworded in tier' "$TF_CARRIER")
  run --separate-stderr bash "$CMD"
}

@test "a line both root and the tier changed apart is written to root as a diff3 chunk under D44's labels" {
  both_reword_the_same_line
  grep -q '^<<<<<<< HEAD$' memory/MEMORY.md || {
    printf 'no chunk in root; the line reads:\n%s\n' "$(grep -F 'shared.md' memory/MEMORY.md)" >&2
    return 1
  }
  # Ours, base and theirs, each under git's vocabulary: HEAD, then the commits
  # the base and the tier carrier were read at.
  grep -qxF -- '- [shared](ddaanet/shared.md) — reworded in root' memory/MEMORY.md
  grep -q "^||||||| ${old_pin:0:7}" memory/MEMORY.md
  grep -qxF -- "$SHARED_ROOT" memory/MEMORY.md
  grep -qxF -- '- [shared](ddaanet/shared.md) — reworded in tier' memory/MEMORY.md
  grep -q "^>>>>>>> ${tier_sha:0:7}" memory/MEMORY.md
  # The tier's other line is adopted outside the chunk.
  grep -qxF -- "$TF_ROOT" memory/MEMORY.md
}

@test "a compose-up left with markers commits nothing and moves no tier back" {
  both_reword_the_same_line
  [ "$(git -C memory rev-parse HEAD)" = "$root_head" ] || {
    printf 'root HEAD moved from %s to %s\n' "$root_head" "$(git -C memory rev-parse HEAD)" >&2
    return 1
  }
  [ "$(git -C memory log -1 --format=%s)" = "root rewords a tier line" ]
  # The tier is where its take put it, on the remote's commit, not on the pin.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_sha" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$tier_sha" ]
}

@test "a compose-up left with markers names the file and the lines and says to resolve the markers and commit memory" {
  both_reword_the_same_line
  all="${output}${stderr}"
  # The pass's own report line names the file whatever the marker message says.
  named=$(printf '%s\n' "$all" | grep -v 'composed ' || true)
  first=$(grep -n '^<<<<<<< ' memory/MEMORY.md | head -n 1 | cut -d: -f1 || true)
  [[ "$named" == *"MEMORY.md"* ]] || { printf 'the run never names the file:\n%s\n' "$all" >&2; return 1; }
  [[ "$all" == *"marker"* ]] || { printf 'the run never mentions markers:\n%s\n' "$all" >&2; return 1; }
  [[ "$all" == *"commit memory"* ]] || { printf 'the run never says to commit memory:\n%s\n' "$all" >&2; return 1; }
  # The lines: the conflicting entry, or the marker's line number.
  [[ "$all" == *"shared.md"* || ( -n "$first" && ( "$all" == *"line $first"* || "$all" == *":$first"* ) ) ]] || {
    printf 'the run never names the conflicting lines:\n%s\n' "$all" >&2
    return 1
  }
}

@test "a chunk resolved to root's own text composes and commits, and no chunk comes back" {
  # The take stages the tier's HEAD when it leaves a chunk, so the next pass and
  # the commit read their base from it: root has seen the tier's version, and a
  # resolution to either side, or to neither, stands.
  both_reword_the_same_line
  grep -vE '^(<<<<<<< |\|\|\|\|\|\|\| |=======$|>>>>>>> )' memory/MEMORY.md \
    | grep -vxF -e "$SHARED_ROOT" -e '- [shared](ddaanet/shared.md) — reworded in tier' \
    > "$BATS_TEST_TMPDIR/resolved"
  cp "$BATS_TEST_TMPDIR/resolved" memory/MEMORY.md
  grep -qxF -- '- [shared](ddaanet/shared.md) — reworded in root' memory/MEMORY.md

  # The in-session pass the resolving edit triggers.
  run --separate-stderr bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ] || { printf 'compose status %s, stderr:\n%s\nroot:\n%s\n' "$status" "$stderr" "$(cat memory/MEMORY.md)" >&2; return 1; }
  run --separate-stderr commit_sections "memory: settle the chunk"
  [ "$status" -eq 0 ] || { printf 'commit status %s, stderr:\n%s\n' "$status" "$stderr" >&2; return 1; }

  run ! grep -qE '^(<<<<<<<|>>>>>>>)' memory/MEMORY.md
  grep -qxF -- '- [shared](ddaanet/shared.md) — reworded in root' memory/MEMORY.md
  grep -qxF -- "$TF_ROOT" memory/MEMORY.md
  # The tier carries root's text in a commit on top of the one the take
  # brought, and memory records that commit.
  [ "$(git -C memory/ddaanet rev-parse HEAD^)" = "$tier_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  git -C memory/ddaanet show HEAD:MEMORY.md | grep -qxF -- '- [shared](shared.md) — reworded in root'
  [ -z "$(git -C memory status --porcelain)" ]

  run --separate-stderr bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- the continuation recomposes before its commit -----------------------------

# Root diverged from its remote (a root-only commit, an upstream commit), and
# the tier's remote holds a fact neither root side records. The take moves the
# tier first; the root merge then stages the tier's HEAD, which makes the tier
# read as on its pin. Leaves the tier's new commit in $tier_sha.
root_diverged_tier_past_both() {
  take_base_store
  printf 'local only\n' > memory/local-only.md
  git -C memory add local-only.md
  git -C memory commit -qm "a root-only fact"
  git -C memory push -q . HEAD:refs/heads/live
  push_memory_fact
  tier_sha=$(push_tier_fact ddaanet "$TF_CARRIER")
}

@test "a tier fact past both sides of a diverged root reaches root's index once the merger has finished, and no orphan is reported" {
  root_diverged_tier_past_both

  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ] || { cat "$BATS_TEST_TMPDIR"/take.*.err >&2; return 1; }
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$tier_sha" ]
  [ -f memory/local-only.md ]
  [ -f memory/REMOTE.md ]
  grep -qxF -- "$TF_ROOT" memory/MEMORY.md || {
    printf 'the tier'\''s line never reached root:\n%s\n' "$(cat memory/MEMORY.md)" >&2
    return 1
  }
  [ -z "$(gitlore_compose_orphans memory)" ] || {
    gitlore_compose_orphans memory >&2
    return 1
  }
  # The merge commit itself carries the line and memory is clean: a
  # continuation that commits first and composes afterwards fails here.
  merge_commit=$(git -C memory rev-list --merges -n 1 HEAD)
  [ -n "$merge_commit" ]
  git -C memory show "$merge_commit:MEMORY.md" | grep -qxF -- "$TF_ROOT" || {
    printf 'the merge commit %s lacks the tier'\''s line:\n%s\n' "$merge_commit" \
      "$(git -C memory show "$merge_commit:MEMORY.md")" >&2
    return 1
  }
  [ -z "$(git -C memory status --porcelain)" ] || {
    git -C memory status --porcelain >&2
    return 1
  }
}

# memory remote: a commit rewording root's line $1 to $2 another way, so git
# conflicts root's MEMORY.md in the merge.
push_memory_reword() {
  local work content
  work="$(mktemp -d "$TMP_REPO/mwork.XXXXXX")"
  git clone -q -b live "$MEMORY_REMOTE" "$work"
  (
    cd "$work" || exit 1
    git config user.email "other@example.com"
    git config user.name "Other"
    content=$(cat MEMORY.md)
    content=${content//"$1"/"$2"}
    printf '%s\n' "$content" > MEMORY.md
    git commit -qam "remote rewords the root line"
    git push -q origin live
  )
  rm -rf "$work"
}

@test "a line root and the tier changed apart takes the tier's in the continuation, reported, and the merge lands" {
  take_base_store
  reword_root_and_commit "a portable fact" "reworded in root"
  push_memory_reword "a portable fact" "reworded on memory remote"
  push_tier_carrier_edit ddaanet "a portable fact" "reworded in tier" >/dev/null

  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ] || { cat "$BATS_TEST_TMPDIR"/take.*.err >&2; return 1; }
  tierline='- [shared](ddaanet/shared.md) — reworded in tier'
  grep -qxF -- "$tierline" memory/MEMORY.md
  run ! grep -q "^<<<<<<< " memory/MEMORY.md
  merge_commit=$(git -C memory rev-list --merges -n 1 HEAD)
  [ -n "$merge_commit" ]
  git -C memory show "$merge_commit:MEMORY.md" | grep -qxF -- "$tierline"
  [ -z "$(git -C memory status --porcelain)" ]
  cat "$BATS_TEST_TMPDIR"/take.*.err | grep -qF "tier 'ddaanet' replaced root's line for ddaanet/shared.md: - [shared](ddaanet/shared.md) — reworded on memory remote"
}
