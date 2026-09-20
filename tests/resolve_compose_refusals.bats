#!/usr/bin/env bats
# Push refusals around the merge continuation: a policy decline on the tier's
# remote, a refused local `live` update and its printed remedy, and the
# default-mode gate on a policy refusal. Split out of resolve_compose.bats.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
# Each @test is its own subshell; a per-test `export GITLORE_GIT_RETRY_SCHEDULE`
# is consumed within that same test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/stub-synth
load helpers/resolve-compose

# Install a pre-receive hook in bare repository $1 that declines every push for
# a reason other than divergence.
decline_pushes_to() {
  printf '#!/bin/sh\necho "declined by policy" >&2\nexit 1\n' > "$1/hooks/pre-receive"
  chmod +x "$1/hooks/pre-receive"
}

@test "an origin push declined for policy rests the unadopted tier and exits 1" {
  prepare_tier_merge_with_new_lines
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"
  pin=$(git -C memory rev-parse :ddaanet)
  ours=$(git -C memory/ddaanet rev-parse HEAD)
  theirs=$(git -C memory/ddaanet rev-parse MERGE_HEAD)
  published=$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)
  decline_pushes_to "$TMP_REPO/.bare-ddaanet.git"

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"declined by policy"* ]]
  [ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)" = "$published" ]
  # The local `. HEAD:live` push ran before the declined one, so the tier's
  # `live` holds the merge of the two sides, and the tier rests on its pin.
  [ "$(git -C memory/ddaanet rev-parse 'live^1')" = "$ours" ]
  [ "$(git -C memory/ddaanet rev-parse 'live^2')" = "$theirs" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]
}

@test "a refused local live update leaves the unadopted tier on the merge with a runnable remedy" {
  prepare_tier_merge_with_new_lines
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"
  pin=$(git -C memory rev-parse :ddaanet)
  ours=$(git -C memory/ddaanet rev-parse HEAD)
  theirs=$(git -C memory/ddaanet rev-parse MERGE_HEAD)
  live_before=$(git -C memory/ddaanet rev-parse live)
  lock="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/refs/heads/live.lock"
  : > "$lock"
  export GITLORE_GIT_RETRY_SCHEDULE=0

  run --separate-stderr bash "$RESOLVE" continue-after-merge
  rm -f "$lock"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"live.lock"* ]]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$live_before" ]
  # The merge commit lands before either push, and the tier stays on it.
  [ "$(git -C memory/ddaanet rev-parse 'HEAD^1')" = "$ours" ]
  [ "$(git -C memory/ddaanet rev-parse 'HEAD^2')" = "$theirs" ]
  abs=$(CDPATH='' cd -- memory/ddaanet && pwd)
  [[ "$stderr" == *"gitlore: tier 'ddaanet' stays on the merge commit because its local 'live' does not hold it. Run:
gitlore:   git -C \"$abs\" push . HEAD:live
gitlore:   git -C \"$abs\" merge-base --is-ancestor HEAD live && git -C \"$abs\" checkout --detach $pin
gitlore: then fix the problems listed above and run /gitlore:merge."* ]]
}

@test "following the remedy adopts the merge" {
  prepare_tier_merge_with_new_lines
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"
  pin=$(git -C memory rev-parse :ddaanet)
  lock="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/refs/heads/live.lock"
  : > "$lock"
  export GITLORE_GIT_RETRY_SCHEDULE=0
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  rm -f "$lock"
  [ "$status" -eq 1 ]
  merged=$(git -C memory/ddaanet rev-parse HEAD)

  # Line by line, so a spaced path stays inside the command that quotes it.
  remedy=()
  while IFS= read -r line; do
    remedy+=("$line")
  done < <(printf '%s\n' "$stderr" | sed -n 's/^gitlore:   \(git -C .*\)$/\1/p')
  [ "${#remedy[@]}" -eq 2 ]
  # From another directory, so a path the remedy leaves relative fails.
  cd "$BATS_TEST_TMPDIR"
  bash -c "${remedy[0]}"
  bash -c "${remedy[1]}"
  cd "$TMP_REPO"
  [ "$(git -C memory/ddaanet rev-parse live)" = "$merged" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$pin" ]

  sed -i.bak '/gone\/x\.md/d' memory/MEMORY.md
  rm -f memory/MEMORY.md.bak
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/merge-memory.sh"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$merged" ]
  grep -qxF -- '- [their fact](ddaanet/t.md) — theirs' memory/MEMORY.md
}

@test "the remedy keeps the tier on the merge while its local live update is still refused" {
  prepare_tier_merge_with_new_lines
  seed_root_bullet "gone/x.md" "a tier that is no longer mounted"
  lock="$(git -C memory/ddaanet rev-parse --absolute-git-dir)/refs/heads/live.lock"
  : > "$lock"
  export GITLORE_GIT_RETRY_SCHEDULE=0
  run --separate-stderr bash "$RESOLVE" continue-after-merge
  [ "$status" -eq 1 ]
  merged=$(git -C memory/ddaanet rev-parse HEAD)

  remedy=()
  while IFS= read -r line; do
    remedy+=("$line")
  done < <(printf '%s\n' "$stderr" | sed -n 's/^gitlore:   \(git -C .*\)$/\1/p')
  [ "${#remedy[@]}" -eq 2 ]
  # The lock still held: the push fails again, and running the next line
  # regardless must not move the tier off a merge no ref holds.
  run bash -c "${remedy[0]}"
  [ "$status" -ne 0 ]
  run bash -c "${remedy[1]}"
  rm -f "$lock"
  [ "$status" -ne 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$merged" ]
}

@test "default-mode gates exit 1 on a policy refusal" {
  make_parent_with_memory
  git -C memory push -q origin live
  decline_pushes_to "$TMP_REPO/.bare-memory.git"
  printf -- '- [new fact](f.md) — mine\n' >> memory/MEMORY.md
  echo mine > memory/f.md
  git -C memory add -A
  approve "memory: add a fact"
  bash "$PRE_COMMIT"
  # Local `live` strictly ahead of the remote's: routed by ancestry, the declined
  # push would read as a non-fast-forward the remote raced.
  git -C memory merge-base --is-ancestor origin/live live
  [ "$(git -C memory rev-parse live)" != "$(git -C memory rev-parse origin/live)" ]

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"declined by policy"* ]]
  [[ "$stderr" == *"not because of divergence"* ]]
  [[ "$stderr" != *"refused as a non-fast-forward"* ]]
}
