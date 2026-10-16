#!/usr/bin/env bash
# The commands scripts/cross-rewrite.sh prints in its refusals (D62, D63): the
# checkout of a store that is absent, the run of record-rewrite.sh that
# publishes a rewrite record, and the from-scratch rebuild of a damaged one. Sourced by that script, which sets
# `script_dir`; it is not run on its own.
# shellcheck disable=SC2154 # script_dir is the sourcing script's

# Prints the command that checks out the store at $1, run from the repository
# whose index holds its gitlink: the repository containing its directory, which
# is the memory store for a tier and the project for the memory store. Each
# path component that is not checked out yet gets its own step, outermost
# first, so a tier whose memory store is absent initializes the store before
# the tier. A directory that is not inside a repository gets the root form.
# Args: $1=store path.
checkout_command() {
  local path="$1" dir top abs rel cur part steps="" parts
  dir=$(dirname "$path")
  if [ -d "$dir" ] && top=$(git -C "$dir" rev-parse --show-toplevel 2>&1); then
    abs="$(cd "$dir" && pwd -P)/$(basename "$path")"
    rel="${abs#"$top"/}"
    IFS=/ read -r -a parts <<< "$rel"
    cur="$top"
    for part in "${parts[@]}"; do
      if [ ! -e "$cur/$part/.git" ]; then
        steps="${steps:+$steps && }git -C \"$cur\" submodule update --init -- \"$part\""
      fi
      cur="$cur/$part"
    done
    printf '%s' "$steps"
  else
    printf 'git submodule update --init -- "%s"' "$path"
  fi
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
  printf '"%s/record-rewrite.sh" "$MIRROR" "$MIRROR/filter-repo/commit-map" %q' "$script_dir" "$(origin_url "$1")"
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
  printf 'Rebuild the record of %s from scratch; nothing repairs it in place. The record is rebuilt from the commit-maps of the rewrites, so a rewrite whose commit-map is no longer at hand drops out of it. %sRun these in order, with one record-rewrite.sh line per commit-map still at hand, oldest rewrite first. The ls-remote line lists the branch once the record is back; then run this again:\n  git -C "%s" push origin --delete gitlore/rewrites\n  "%s/record-rewrite.sh" "%s" "%s"\n  git -C "%s" ls-remote origin gitlore/rewrites' \
    "$repo" "$placeholder" "$repo" "$script_dir" "$repo" "$map" "$repo"
}
