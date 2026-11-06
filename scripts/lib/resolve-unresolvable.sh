#!/usr/bin/env bash
# Unresolvable pins: a recorded commit that the repository which should hold it
# lacks, whether memory's gitlink on a tier or the parent's pin on memory. It is
# an integrity error at every level: nothing composes over it and nothing is
# recorded under it, so the pin never moves backward silently. SessionStart and
# /gitlore:resolve report it, naming the commit, the remote that lacks it, and
# the repo `.gitmodules` names when that is a different one. The remedy is per
# level: the checkout that recorded a tier gitlink publishes it with
# /gitlore:push, or /gitlore:resolve reverts the memory commit that recorded it
# when that checkout is gone; a parent pin means the memory holding it has not
# been merged upstream, which no command here changes.
# Part of lib/resolve.sh; source that, not this file.

# Print the commit memory's index records for tier $2 when this checkout of the
# tier does not hold it, and nothing otherwise. Local only: whether the remote
# holds it is the caller's fetch. The index, not HEAD, as the pin guard reads it:
# a staged gitlink is what the next memory commit records.
# Args: $1 = memory worktree path, $2 = tier path.
gitlore_tier_pin_absent() {
  local mempath="$1" tier="$2" pin
  # `git -C` into an unmaterialized submodule answers for the enclosing repo.
  [ -e "$mempath/$tier/.git" ] || return 0
  pin=$(git -C "$mempath" rev-parse -q --verify ":$tier") || return 0
  git -C "$mempath/$tier" rev-parse -q --verify "$pin^{commit}" >/dev/null && return 0
  printf '%s\n' "$pin"
}

# Print the commit the parent's index records for memory when the memory store
# does not hold it, and nothing otherwise. Run from the parent's root.
# Args: $1 = memory worktree path.
gitlore_parent_pin_absent() {
  local mempath="$1" pin
  pin=$(git rev-parse -q --verify ":$mempath") || return 0
  git -C "$mempath" rev-parse -q --verify "$pin^{commit}" >/dev/null && return 0
  printf '%s\n' "$pin"
}

# The report line for tier $2, whose recorded commit $3 neither the checkout nor
# its remote holds. Carries the push remedy and the revert, and no command that
# needs the commit: a checkout of it or a merge that fetches it both fail.
# Args: $1 = memory worktree path, $2 = tier path, $3 = the recorded commit.
gitlore_unresolvable_tier_report() {
  local mempath="$1" tier="$2" pin="$3" remote recorded where
  remote=$(git -C "$mempath/$tier" config --get remote.origin.url || true)
  if [ -n "$remote" ]; then
    where="neither this checkout of the tier nor its remote $remote holds"
  else
    where="this checkout of the tier does not hold, and the tier has no remote"
  fi
  recorded=$(gitlore_gitmodules_url "$mempath/.gitmodules" "$tier")
  if [ -n "$recorded" ] && { [ -z "$remote" ] || ! gitlore_same_repo_url "$remote" "$recorded"; }; then
    where="$where; $mempath/.gitmodules names $recorded for the tier, a different repo"
  fi
  printf "gitlore: memory records tier '%s' at %s, a commit %s. Nothing composes over it. The checkout that recorded it publishes it with /gitlore:push; if that checkout no longer exists, /gitlore:resolve reverts the memory commit that recorded it.\n" \
    "$tier" "${pin:0:12}" "$where"
}

# The report line for the parent's pin $2 on memory, which memory's remote does
# not hold. No command and no url change: whether to accept another repo's url
# belongs to the multi-repo design, not to this report.
# Args: $1 = memory worktree path, $2 = the recorded commit.
gitlore_unresolvable_parent_report() {
  local mempath="$1" pin="$2" remote recorded where
  remote=$(git -C "$mempath" config --get remote.origin.url || true)
  if [ -n "$remote" ] && ! gitlore_is_placeholder_url "$remote"; then
    where="a commit memory's remote $remote does not hold"
  else
    where="a commit this memory store does not hold, and memory has no remote"
  fi
  recorded=$(gitlore_gitmodules_url .gitmodules "$mempath")
  if [ -n "$recorded" ] && { [ -z "$remote" ] || ! gitlore_same_repo_url "$remote" "$recorded"; }; then
    where="$where; .gitmodules names $recorded for memory, a different repo"
  fi
  printf 'gitlore: this repository records memory at %s, %s. The memory holding it has not been merged upstream, so its facts are not in this checkout.\n' \
    "${pin:0:12}" "$where"
}

# Print the url .gitmodules file $1 records for the submodule at path $2, or
# nothing. `-z` keeps a name or path with spaces in one record.
# Args: $1 = .gitmodules file, $2 = submodule path.
gitlore_gitmodules_url() {
  local file="$1" want="$2" rec key name
  # C for the function's span, since bash 3.2 ignores a locale assigned in front
  # of a builtin: a NUL-delimited `read` under a multibyte locale overshoots in
  # bash 5.0-5.3 (BP#65).
  local LC_ALL=C
  [ -f "$file" ] || return 0
  while IFS= read -r -d '' rec; do
    [ "${rec#*$'\n'}" = "$want" ] || continue
    key=${rec%%$'\n'*}
    name=${key#submodule.}
    name=${name%.path}
    git config --file "$file" --get "submodule.$name.url" || true
    return 0
  done < <(git config --file "$file" -z --get-regexp '^submodule\..*\.path$')
  return 0
}

# Exit 0 when urls $1 and $2 name one repository. By D64 `.gitmodules` records
# a GitHub repo in its https form while the module's own remote can stay on ssh,
# so both go through the same https form before a trailing `/` and `.git` are
# dropped; any other pair compares as written.
gitlore_same_repo_url() {
  local a b
  a=$(gitlore_github_https_url "$1")
  b=$(gitlore_github_https_url "$2")
  a=${a%/}
  a=${a%.git}
  b=${b%/}
  b=${b%.git}
  [ "$a" = "$b" ]
}

# /gitlore:resolve's check: report every unresolvable pin under this parent on
# stderr and return 1, or return 0 when there is none. A recorded commit the
# module lacks gets one fetch of the module's `live` first, since a commit only
# its remote holds is a take's business, not an integrity error.
# Args: $1 = memory worktree path.
gitlore_resolve_check_pins() {
  local mempath="$1" tier pin found=0 repo root msg
  repo=$(git rev-parse --show-toplevel)
  root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    pin=$(gitlore_tier_pin_absent "$mempath" "$tier")
    [ -n "$pin" ] || continue
    if [ -n "$(git -C "$mempath/$tier" config --get remote.origin.url || true)" ]; then
      gitlore_git -C "$mempath/$tier" fetch -q --no-recurse-submodules origin live || true
    fi
    pin=$(gitlore_tier_pin_absent "$mempath" "$tier")
    [ -n "$pin" ] || continue
    found=1
    msg="$(gitlore_unresolvable_tier_report "$mempath" "$tier" "$pin")
gitlore: once no checkout holds it, revert the memory commit that recorded it on live, keeping it in history:
gitlore:   cd \"$repo\" && bash \"$root/scripts/resolve.sh\" revert-pin $(printf '%q' "$tier")"
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
  done < <(gitlore_tier_paths "$mempath")

  pin=$(gitlore_parent_pin_absent "$mempath")
  if [ -n "$pin" ]; then
    gitlore_git -C "$mempath" fetch -q --no-recurse-submodules origin live || true
    pin=$(gitlore_parent_pin_absent "$mempath")
  fi
  if [ -n "$pin" ]; then
    found=1
    msg=$(gitlore_unresolvable_parent_report "$mempath" "$pin")
    gitlore_say_for_agent_or_user "$msg" "$msg" >&2
  fi
  [ "$found" -eq 0 ]
}

# `resolve.sh revert-pin <tier>`: revert, on memory's `live`, the memory commit
# that recorded tier $2 at a commit no repository holds. A revert and never a
# reset, so the commit stays in history and the root lines it carried go with
# it; a holder found alive afterwards sits ahead of the reverted pin, and the
# compose re-adopts its lines. Publishing the revert is /gitlore:push's.
# Returns 1 after saying why on stderr when nothing was reverted.
# Args: $1 = memory worktree path, $2 = tier path.
gitlore_revert_lost_pin() {
  local mempath="$1" tier="$2" lost rec parents head live msg
  if [ ! -e "$mempath/$tier/.git" ]; then
    echo "gitlore: tier '$tier' is not checked out in $mempath, so whether it holds its recorded commit cannot be told; nothing was reverted." >&2
    return 1
  fi
  if gitlore_any_store_mid_merge "$mempath"; then
    echo "gitlore: a merge is prepared in the memory store or a tier; land or abort it before reverting. Nothing was reverted." >&2
    return 1
  fi
  # The tiers are left out: the lost tier is checked out off the commit memory
  # records by definition, and a revert writes no tier's worktree.
  if [ -n "$(git -C "$mempath" status --porcelain --ignore-submodules=all)" ]; then
    echo "gitlore: memory has uncommitted changes; commit them first. Nothing was reverted." >&2
    return 1
  fi
  head=$(git -C "$mempath" rev-parse HEAD)
  live=$(git -C "$mempath" rev-parse -q --verify refs/heads/live) || live=""
  if [ "$head" != "$live" ]; then
    echo "gitlore: memory's HEAD is not on its live; run /gitlore:merge first. Nothing was reverted." >&2
    return 1
  fi
  if ! lost=$(git -C "$mempath" rev-parse -q --verify "live:$tier"); then
    echo "gitlore: memory's live records no commit for tier '$tier'; nothing was reverted." >&2
    return 1
  fi
  if [ -n "$(git -C "$mempath/$tier" config --get remote.origin.url || true)" ]; then
    gitlore_git -C "$mempath/$tier" fetch -q --no-recurse-submodules origin live || true
  fi
  if git -C "$mempath/$tier" rev-parse -q --verify "$lost^{commit}" >/dev/null; then
    echo "gitlore: tier '$tier' holds the commit memory records for it (${lost:0:12}), so there is nothing to revert. Run /gitlore:merge." >&2
    return 1
  fi
  # The most recent commit on live that touched the gitlink is the one that set
  # it to the commit live records.
  rec=$(git -C "$mempath" log -1 --format=%H live -- "$tier")
  if [ -z "$rec" ] || [ "$(git -C "$mempath" rev-parse -q --verify "$rec:$tier")" != "$lost" ]; then
    echo "gitlore: no commit on memory's live records tier '$tier' at ${lost:0:12}; nothing was reverted." >&2
    return 1
  fi
  # `rev-list --parents` prints fixed-width hex ids and nothing else, so a word
  # count carries none of the usual splitting hazard.
  parents=$(git -C "$mempath" rev-list --parents -n 1 "$rec" | wc -w | tr -d ' ')
  if [ "$parents" -ne 2 ]; then
    echo "gitlore: tier '$tier' was recorded at ${lost:0:12} by merge commit ${rec:0:12}, which this does not revert. Revert it by hand with git revert -m 1. Nothing was reverted." >&2
    return 1
  fi
  if ! gitlore_git -C "$mempath" revert --no-edit "$rec" >&2; then
    if git -C "$mempath" rev-parse -q --verify REVERT_HEAD >/dev/null; then
      gitlore_git -C "$mempath" revert --abort >&2 || true
    fi
    echo "gitlore: the revert of memory commit ${rec:0:12} did not apply cleanly, so it was abandoned and memory is as it was." >&2
    return 1
  fi
  gitlore_git -C "$mempath" push -q . HEAD:refs/heads/live >&2
  msg="gitlore: reverted memory commit ${rec:0:12}, which recorded tier '$tier' at ${lost:0:12}, on live; the commit stays in history. Run /gitlore:push to publish the revert."
  gitlore_say_for_agent_or_user "$msg" "$msg" >&2
}
