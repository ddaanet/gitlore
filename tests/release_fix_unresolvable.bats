#!/usr/bin/env bats
# Two refusals of the unresolvable-pin path (docs/references/unresolvable-pin.md).
# A tier fetch that fails cannot tell an unfetched commit from a lost one, so
# neither /gitlore:resolve nor `revert-pin` reads it as the remote lacking the
# pin. And `revert-pin` refusing a memory store with uncommitted changes gives a
# remedy that can be followed: a commit cannot, since the pin guard refuses a
# commit over a tier pin the tier lacks.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/merge-memory
load helpers/take-order
load helpers/unresolvable-pin

# Memory's live records tier ddaanet at a commit the tier's remote holds and
# this checkout of the tier lacks, and the tier's remote url names no
# repository, so the fetch that would bring the commit fails. Leaves $held and
# $recording.
tier_pin_behind_an_unreachable_remote() {
  take_base_store
  held=$(push_tier_fact ddaanet "- [held](held.md) — on the remote")
  git -C memory update-index --add --cacheinfo "160000,$held,ddaanet"
  git -C memory commit -qm "record a tier commit its remote holds"
  git -C memory push -q . HEAD:refs/heads/live
  git -C memory push -q origin live
  recording=$(git -C memory rev-parse HEAD)
  git -C "$TMP_REPO/.bare-ddaanet.git" cat-file -e "$held^{commit}"
  git -C memory/ddaanet config remote.origin.url "$TMP_REPO/.no-such-remote.git"
  run ! git -C memory/ddaanet rev-parse -q --verify "$held^{commit}"
}

@test "/gitlore:resolve does not report a pin as one the tier's remote lacks when the fetch of that remote failed" {
  tier_pin_behind_an_unreachable_remote
  CLAUDECODE='' run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh"
  all=$(said)
  # Positive first: the resolver names the pin and does not call the store
  # healthy over it.
  [ "$status" -ne 0 ]
  [[ "$all" != *"healthy"* ]] || { printf 'resolve calls the store healthy:\n%s\n' "$all" >&2; return 1; }
  [[ "$all" == *"${held:0:12}"* ]] || { printf 'resolve never names %s:\n%s\n' "${held:0:12}" "$all" >&2; return 1; }
  [[ "$all" != *"nor its remote"* ]] || {
    printf 'resolve says the remote lacks a commit it never read:\n%s\n' "$all" >&2
    return 1
  }
  [[ "$all" != *"revert-pin"* ]] || {
    printf 'resolve offers the revert over a commit the remote may hold:\n%s\n' "$all" >&2
    return 1
  }
}

@test "revert-pin reverts nothing when the fetch of the tier's remote failed" {
  tier_pin_behind_an_unreachable_remote
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh" revert-pin ddaanet
  [ "$(git -C memory rev-parse live)" = "$recording" ] || {
    printf 'revert-pin moved live over a commit the remote may hold:\n%s\n' "$(said)" >&2
    return 1
  }
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Nothing was reverted"* ]]
}

@test "revert-pin refusing uncommitted changes gives a remedy that, followed, reverts and keeps the changes" {
  tier_gitlink_nobody_holds
  # The lost tier sits off the commit memory records, here ahead of it.
  printf 'local\n' > memory/ddaanet/local.md
  git -C memory/ddaanet add local.md
  git -C memory/ddaanet commit -qm "a local tier commit"
  # A tracked edit to root's index, away from the lines the reverted commit
  # added, and an untracked fact file.
  printf '%s\n' "<!-- an edit in progress -->" "$(cat memory/MEMORY.md)" > memory/MEMORY.md.new
  mv memory/MEMORY.md.new memory/MEMORY.md
  printf 'a new fact\n' > memory/new-fact.md
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh" revert-pin ddaanet
  [ "$status" -ne 0 ]
  [ "$(git -C memory rev-parse live)" = "$recording" ]
  # The commands the refusal names, each a line `cd "<dir>" && ...`, in order.
  cmds=$(printf '%s\n' "$stderr" | sed -n 's/^gitlore:[[:space:]]*\(cd "[^"]*" && .*\)$/\1/p')
  [ "$(printf '%s\n' "$cmds" | grep -c .)" -eq 3 ] || {
    printf 'the refusal names no three-step remedy:\n%s\n' "$stderr" >&2
    return 1
  }
  while IFS= read -r cmd; do
    run --separate-stderr bash -c "$cmd"
    [ "$status" -eq 0 ] || { printf 'remedy step failed: %s\n%s\n%s\n' "$cmd" "$output" "$stderr" >&2; return 1; }
  done <<<"$cmds"
  git -C memory merge-base --is-ancestor "$recording" live
  [ "$(git -C memory rev-parse live)" != "$recording" ]
  [ "$(git -C memory rev-parse live:ddaanet)" = "$gitlink_before" ]
  grep -qF 'a new fact' memory/new-fact.md
  grep -qF 'an edit in progress' memory/MEMORY.md
  # Nothing left staged for the next commit to record by surprise.
  git -C memory diff --cached --quiet
}
