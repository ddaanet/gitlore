#!/usr/bin/env bash
# The commands scripts/cross-rewrite.sh prints in its refusals (D62, D63): the
# checkout of a store that is absent, the run of record-rewrite.sh that
# publishes a rewrite record, the from-scratch rebuild of a damaged one, and
# the moves that resolve a ref on a dropped commit. Sourced by that script,
# which sets `script_dir`, `store`, ZEROS and defines `refuse` and `fetch_main`;
# it is not run on its own.
# shellcheck disable=SC2154 # script_dir, store and ZEROS are the sourcing script's

# Prints the command that checks out the store at $1, run from the repository
# whose index holds its gitlink: the nearest repository containing its
# directory, which is the memory store for a tier and the project for the
# memory store. Each gitlink on the way that is not checked out yet gets its own
# step, outermost first, so a tier whose memory store is absent initializes the
# store before the tier. A plain directory on the way is part of the gitlink's
# path, not a step of its own; the index of a store that is not checked out
# cannot be read, so a component under one gets a step only if it is the store
# itself. A directory that is not inside a repository gets the root form.
# Args: $1=store path.
checkout_command() {
  local path="$1" dir top abs rel root sub part i last steps="" parts
  dir=$(dirname "$path")
  if [ -d "$dir" ] && top=$(git -C "$dir" rev-parse --show-toplevel 2>&1); then
    abs="$(cd "$dir" && pwd -P)/$(basename "$path")"
    rel="${abs#"$top"/}"
    IFS=/ read -r -a parts <<< "$rel"
    last=$((${#parts[@]} - 1))
    root="$top"
    sub=""
    for i in "${!parts[@]}"; do
      part="${parts[$i]}"
      sub="${sub:+$sub/}$part"
      if [ -e "$root/$sub/.git" ]; then
        root="$root/$sub"
        sub=""
      elif [ "$i" -eq "$last" ] || { [ -e "$root/.git" ] && is_gitlink "$root" "$sub"; }; then
        steps="${steps:+$steps && }git -C $(dq "$root") submodule update --init -- $(dq "$sub")"
        root="$root/$sub"
        sub=""
      fi
    done
    printf '%s' "$steps"
  else
    printf 'git submodule update --init -- %s' "$(dq "$path")"
  fi
}

# Succeeds when the path $2 is a gitlink, mode 160000, in the index of the
# repository $1. A directory holding a gitlink is not one itself. Args: $1=repo,
# $2=path within it.
is_gitlink() {
  local rec
  while IFS= read -r -d '' rec; do
    if [ "${rec:0:7}" = "160000 " ] && [ "${rec#*$'\t'}" = "$2" ]; then
      return 0
    fi
  done < <(git -C "$1" --literal-pathspecs ls-files -s -z -- "$2")
  return 1
}

# Prints the URL of the origin of the repository $1, made absolute when it is a
# local path, since the commands that carry it run from another directory.
# Args: $1=repo.
origin_url() {
  local url
  url=$(git -C "$1" remote get-url origin)
  case "$url" in
    *://* | /* | *:*) ;;
    *) [ ! -d "$1/$url" ] || url=$(cd "$1/$url" && pwd -P) ;;
  esac
  printf '%s' "$url"
}

# Prints the record-rewrite.sh invocation that publishes the rewrite record to
# the origin of the repository $1. The commit-map is the one filter-repo wrote
# in the rewritten mirror, which only that mirror has. Args: $1=repo.
record_command() {
  # shellcheck disable=SC2016 # $MIRROR stays literal: the reader sets it
  printf '%s "$MIRROR" "$MIRROR/filter-repo/commit-map" %q' "$(dq "$script_dir/record-rewrite.sh")" "$(origin_url "$1")"
}

# Prints the steps that rebuild the damaged record at the origin of the
# repository $1 from scratch: delete the record branch there, then record each
# commit-map still at hand, oldest rewrite first. A commit-map is filter-repo's
# file in the git dir of the clone that ran the rewrite: the repository's own
# when it has one, otherwise a placeholder the reader replaces. Every printed
# command is absolute. Args: $1=repo.
rebuild_steps() {
  local repo map own_map placeholder="" ref
  repo=$(cd "$1" && pwd -P)
  ref=$(git -C "$repo" rev-parse --git-path filter-repo/commit-map)
  case "$ref" in /*) own_map="$ref" ;; *) own_map="$repo/$ref" ;; esac
  if [ -e "$own_map" ]; then
    map="$own_map"
  else
    map="<commit-map>"
    placeholder="The commit-map is in .git/filter-repo/commit-map of the clone that ran the rewrite; replace <commit-map> with its path. "
  fi
  printf 'Rebuild the record of %s from scratch; nothing repairs it in place. The record is rebuilt from the commit-maps of the rewrites, so a rewrite whose commit-map is no longer at hand drops out of it. %sRun these in order, with one record-rewrite.sh line per commit-map still at hand, oldest rewrite first. The owner runs them when no clone is publishing: between the delete and the first record-rewrite.sh run the remote has no record. The ls-remote line lists the branch once the record is back; then run this again:\n  git -C %s push origin --delete gitlore/rewrites\n  %s %s %s\n  git -C %s ls-remote origin gitlore/rewrites' \
    "$repo" "$placeholder" "$(dq "$repo")" "$(dq "$script_dir/record-rewrite.sh")" "$(dq "$repo")" "$(dq "$map")" "$(dq "$repo")"
}

# Refuses a ref whose record chain ends in a dropped commit, printing the act
# that resolves it. A ref on the dropped commit itself ($3 equals $2) holds no
# local work, so only the move to the remote's tip is printed; a ref above it
# prints the listing of that work and the replay onto the tip. The tip is the
# remote's `live`, or its `main` for main, which is fetched here. A HEAD with
# work that is attached to a branch replays onto that branch's tip and ends
# with the branch's update-ref, so one replay settles both. Args: $1=ref name,
# $2=the ref's commit, $3=the recorded commit whose chain is dropped.
refuse_dropped() {
  local name="$1" sha="$2" base="$3" tip=refs/remotes/origin/live move replay s
  local branch="" ref_arg
  s=$(dq "$store")
  if [ "$name" = HEAD ] && [ "$base" != "$sha" ]; then
    branch=$(git -C "$store" symbolic-ref -q HEAD || true)
    branch=${branch#refs/heads/}
  fi
  if [ "$name" = main ] || [ "$branch" = main ]; then
    fetch_main
    tip=refs/remotes/origin/main
    if ! git -C "$store" rev-parse -q --verify "$tip" > /dev/null; then
      refuse_dropped_no_main "$sha" "$base"
    fi
  fi
  if [ "$name" = HEAD ]; then
    move="git -C $s checkout --detach $tip"
  else
    move="git -C $s update-ref refs/heads/$name $tip"
  fi
  if [ "$base" = "$sha" ]; then
    refuse "$name of $store is at ${sha:0:7}, and its record chain ends in a dropped commit ($ZEROS). Nothing was moved. It holds no local work, so move it to the remote's tip, then run this again:
  $move"
  fi
  replay="git -C $s checkout --detach $tip
  git -C $s cherry-pick $base..$sha"
  if [ "$name" != HEAD ]; then
    branch="$name"
  fi
  if [ -n "$branch" ]; then
    printf -v ref_arg '%q' "refs/heads/$branch"
    replay="$replay
  git -C $s update-ref $ref_arg HEAD"
  fi
  refuse "$name of $store has local commits on top of $base, a recorded commit whose record chain ends in a dropped commit ($ZEROS). Nothing was moved. List the local work, replay it onto the remote's tip, then run this again:
  git -C $s log --oneline $base..$sha
  $replay"
}

# Refuses a dropped main, or a HEAD attached to it, when the origin has no
# main to move it to: with no
# local work the ref is deleted, which leaves it crossed; with some, the
# listing is all there is to print. Args: $1=main's commit, $2=the recorded
# commit whose chain is dropped.
refuse_dropped_no_main() {
  local sha="$1" base="$2" s
  s=$(dq "$store")
  if [ "$base" = "$sha" ]; then
    refuse "main of $store is at ${sha:0:7}, and its record chain ends in a dropped commit ($ZEROS), but the origin has no main to move it to. Nothing was moved. It holds no local work, so delete it, then run this again:
  git -C $s update-ref -d refs/heads/main"
  fi
  refuse "main of $store has local commits on top of $base, a recorded commit whose record chain ends in a dropped commit ($ZEROS), and the origin has no main to replay them onto. Nothing was moved. A person must decide what becomes of them. List them with:
  git -C $s log --oneline $base..$sha"
}

# Prints $1 as one double-quoted shell word that reads back as $1: the four
# characters that stay special inside double quotes are escaped. Character by
# character, since bash 3.2 and 5 disagree on backslashes in ${s//x/y}.
# Args: $1=text.
dq() {
  local s="$1" out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      \\ | '"' | '$' | '`') out="$out\\$c" ;;
      *) out="$out$c" ;;
    esac
  done
  printf '"%s"' "$out"
}
