#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/merge-memory

# A repair beside other problems: a welded line, an interleaved non-bullet
# line, a root problem waiting alongside, an arrival the repair cannot fix,
# and a local `live` that ran ahead of the pin with a defective carrier.

@test "a take repairs a welded line that arrived" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_files ddaanet "$(printf -- '- [A](welded_a.md) — a- [B](welded_b.md) — b')" welded_b.md)
  # Premise: the arrival really carries the weld, unsplit.
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" show "$remote_sha:MEMORY.md" | grep -cxF -- '- [A](welded_a.md) — a- [B](welded_b.md) — b')" -eq 1 ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(git -C memory/ddaanet log -1 --format=%s "$R")" = "Repair the MEMORY.md structure ddaanet received" ]
  [[ "$(git -C memory/ddaanet log -1 --format=%b "$R")" == *"split a welded line before welded_b.md"* ]]
  [ "$(git -C memory/ddaanet show "$R:MEMORY.md" | tail -n 2)" = "$(printf -- '- [A](welded_a.md) — a\n- [B](welded_b.md) — b')" ]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: split a welded line before welded_b.md"* ]]
}

# push_tier_fact commits carrier lines alone; a weld's second path must also
# name a file in the tier for gitlore_repair_index to split it. Shaped like
# push_tier_fact: a plain clone commits the line plus each named file and pushes
# `live`. Args: $1 = tier, $2 = carrier line(s), then the files to create.
push_tier_files() {
  local tier="${1:-ddaanet}" line="$2"; shift 2
  local bare="$TMP_REPO/.bare-$tier.git" work
  work="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-tier-work.XXXXXX")"
  git clone -q "$bare" "$work"
  (
    cd "$work" || exit 1
    git config user.email "test@example.com"
    git config user.name  "Test"
    git checkout -q -B live origin/live
    printf '%s\n' "$line" >> MEMORY.md
    local f
    for f in "$@"; do
      printf 'body\n' > "$f"
    done
    git add -A
    git commit -qm "remote tier fact"
    git push -q origin live
  )
  git -C "$work" rev-parse HEAD
  rm -rf "$work"
}

@test "a take repairs an interleaved non-bullet line that arrived" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\nStray line here\n- [B](b.md) — y')")
  # Premise: the arrival really carries the stray line inside the bullet block.
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" show "$remote_sha:MEMORY.md" | tail -n 3)" = "$(printf -- '- [A](a.md) — x\nStray line here\n- [B](b.md) — y')" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(git -C memory/ddaanet log -1 --format=%s "$R")" = "Repair the MEMORY.md structure ddaanet received" ]
  [[ "$(git -C memory/ddaanet log -1 --format=%b "$R")" == *"moved a non-bullet line out of the pointer block: Stray line here"* ]]
  [ "$(git -C memory/ddaanet show "$R:MEMORY.md" | tail -n 3)" = "$(printf -- '- [A](a.md) — x\n- [B](b.md) — y\nStray line here')" ]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: moved a non-bullet line out of the pointer block: Stray line here"* ]]
}

@test "a repair beside a root problem lands in live and waits" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [A](a.md) — x\n- [A](a.md) — x')")
  memhead=$(git -C memory rev-parse HEAD)
  # Premise: root really carries the leftover prefix, committed.
  git -C memory show HEAD:MEMORY.md | grep -qF 'gone/x.md'

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [[ "$all" == *"gone/x.md"* ]]
  [[ "$all" == *"gitlore: repaired ddaanet's arrival: dropped a duplicate pointer line: - [A](a.md) — x"* ]]
  [[ "$stderr" == *"its local 'live' keeps the repair."* ]]
  [[ "$stderr" != *"keeps what arrived"* ]]
  # What adoption waits on is the root problem alone: the first refusal's
  # carrier problem, already repaired, is not reported.
  run ! grep -qF 'duplicate pointer path' <<<"$all"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$gitlink" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  R=$(git -C memory/ddaanet rev-parse live)
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $remote_sha" ]
  [ "$(git -C memory rev-parse HEAD)" = "$memhead" ]

  sed -i.bak '/gone\/x\.md/d' memory/MEMORY.md
  rm -f memory/MEMORY.md.bak

  # The next take adopts R as it stands: no second repair commit.
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"repaired"* ]]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory/ddaanet rev-list --count "$remote_sha..live")" -eq 1 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$R" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
}

@test "an arrival the repair cannot fix walks back and names upstream" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  memory_head_before=$(git -C memory rev-parse HEAD)
  gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [B](b.md) — y\n- [B](b.md) — y\n- [a](a.md) — a- [z](z.md) — z')")
  arrival_text=$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" show "$remote_sha:MEMORY.md")
  weld_line_n=$(printf '%s\n' "$arrival_text" | grep -nxF -- '- [a](a.md) — a- [z](z.md) — z' | cut -d: -f1)
  dup_line_n=$(printf '%s\n' "$arrival_text" | grep -nxF -- '- [B](b.md) — y' | head -n 1 | cut -d: -f1)
  # Premise: the identical duplicate sits above the weld, so dropping it moves
  # the weld up a line and the arrival's numbering differs from the repaired
  # copy's; and z.md names no file in the arrival, so the weld guard holds.
  [ -n "$weld_line_n" ]
  [ -n "$dup_line_n" ]
  [ "$dup_line_n" -lt "$weld_line_n" ]
  run ! git --git-dir="$TMP_REPO/.bare-ddaanet.git" cat-file -e "$remote_sha:z.md"
  gitdir_before=$(tier_gitdir_files ddaanet)
  tmp_env="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$tmp_env"

  TMPDIR="$tmp_env" run --separate-stderr bash "$CMD"
  # The unrepairable arm walks the tier back rather than falling through to a
  # commit: the root's own HEAD never moves for a take it refused.
  [ "$(git -C memory rev-parse HEAD)" = "$memory_head_before" ]
  [ "$status" -eq 1 ]
  all="$output$stderr"
  [[ "$all" == *"gitlore: tier 'ddaanet' took an index the take cannot repair; it is held in the tier's local 'live' and must be fixed where it was published:"* ]]
  [[ "$all" == *"live:MEMORY.md: line $weld_line_n welds"* ]]
  [[ "$all" != *"line $((weld_line_n - 1)) welds"* ]]
  # Nothing here names the carrier: every problem in this refusal is the
  # carrier's own, already listed above in its live:MEMORY.md form.
  ! grep -Eq '^gitlore:   .*ddaanet/MEMORY\.md: ' <<<"$stderr" || false
  # The closing remedy points upstream too, never at this store's clean carrier.
  [[ "$all" == *"its local 'live' keeps what arrived. Once the index is fixed where it was published, run /gitlore:merge again."* ]]
  [[ "$all" != *"Fix the store"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$gitlink" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]
  run ! grep -qxF 'Repair the MEMORY.md structure ddaanet received' < <(git -C memory/ddaanet log --all --reflog --format=%s)
  [ "$(tier_gitdir_files ddaanet)" = "$gitdir_before" ]
  [ -z "$(repair_scratch_dirs "$tmp_env")" ]
}

@test "an arrival the repair cannot fix beside a root duplicate reports both and the two-fix remedy" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  remote_sha=$(push_tier_fact ddaanet "$(printf -- '- [B](b.md) — y\n- [B](b.md) — y\n- [a](a.md) — a- [z](z.md) — z')")
  run ! git --git-dir="$TMP_REPO/.bare-ddaanet.git" cat-file -e "$remote_sha:z.md"
  # Root carries an uncommitted duplicate pointer alongside the unrepairable arrival.
  seed_root_bullet "dup.md" "root dup"
  seed_root_bullet "dup.md" "root dup"
  [ "$(grep -cF '(dup.md)' memory/MEMORY.md)" -eq 2 ]
  run ! git -C memory diff --quiet -- MEMORY.md

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *$'\ngitlore:   live:MEMORY.md:'* ]]
  [[ "$stderr" == *"gitlore: the root index could not take tier 'ddaanet''s lines:"$'\n'"gitlore:   memory/MEMORY.md: duplicate pointer path dup.md"* ]]
  # Only the lines not naming the carrier go under that header: the carrier's
  # are already listed in their live:MEMORY.md form.
  [[ "$stderr" != *"memory/ddaanet/MEMORY.md:"* ]]
  [[ "$stderr" == *"Fix the problems listed above in this repo; once the index is fixed where it was published, run /gitlore:merge again." ]]
}

@test "a local live that ran ahead with a defective carrier is repaired" {
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin live:live
  git -C memory/ddaanet checkout -q --detach live
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory rev-parse ":ddaanet")
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]

  # The stranding helper seeds this bullet again, so its commit carries it twice.
  seed_tier_bullet ddaanet local.md "committed here, never recorded"
  strand_live_ahead_of_pin ddaanet
  stranded=$(git -C memory/ddaanet rev-parse live)
  # Premise: live really ran ahead of the pin, carrying the duplicate.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ "$stranded" != "$pin" ]
  [ "$(git -C memory/ddaanet show "$stranded:MEMORY.md" | grep -cxF -- '- [local](local.md) — committed here, never recorded')" -eq 2 ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  # Reached through the local adoption, not a remote fast-forward.
  [[ "$output$stderr" == *"held commits the memory store never recorded; adopted them at $(git -C memory/ddaanet rev-parse --short "$stranded")."* ]]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $stranded" ]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: dropped a duplicate pointer line: - [local](local.md) — committed here, never recorded"* ]]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
  [ "$(grep -cxF -- '- [local](ddaanet/local.md) — committed here, never recorded' memory/MEMORY.md)" -eq 1 ]
}

@test "a refused live update after the repair leaves no trace" {
  export GITLORE_GIT_RETRY_SCHEDULE=0
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin live:live
  git -C memory/ddaanet checkout -q --detach live
  gitlore_compose memory
  commit_memory_state
  pin=$(git -C memory rev-parse ":ddaanet")
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]

  seed_tier_bullet ddaanet local.md "committed here, never recorded"
  strand_live_ahead_of_pin ddaanet
  stranded=$(git -C memory/ddaanet rev-parse live)
  [ "$stranded" != "$pin" ]
  [ "$(git -C memory/ddaanet show "$stranded:MEMORY.md" | grep -cxF -- '- [local](local.md) — committed here, never recorded')" -eq 2 ]

  # A submodule's gitdir lives under memory's own; resolve it, never assume.
  lock="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/refs/heads/live.lock"
  [ -f "$(git -C memory/ddaanet rev-parse --absolute-git-dir)/refs/heads/live" ]
  gitdir_before=$(tier_gitdir_files ddaanet)
  : > "$lock"

  run --separate-stderr bash "$CMD"
  rm -f "$lock"
  [ "$status" -eq 1 ]
  all="$output$stderr"
  # The lock bit after the adoption checked `live` out, i.e. at R's push.
  [[ "$all" == *"held commits the memory store never recorded; adopted them at"* ]]
  [[ "$all" == *"live.lock"* ]]
  [[ "$all" != *"repaired ddaanet's arrival:"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$stranded" ]
  run ! grep -qxF 'Repair the MEMORY.md structure ddaanet received' < <(git -C memory/ddaanet log --all --reflog --format=%s)
  [ "$(tier_gitdir_files ddaanet)" = "$gitdir_before" ]

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"gitlore: repaired ddaanet's arrival: dropped a duplicate pointer line: - [local](local.md) — committed here, never recorded"* ]]
  R=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$(git -C memory/ddaanet rev-parse live)" = "$R" ]
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 "$R")" = "$R $stranded" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$R" ]
}

