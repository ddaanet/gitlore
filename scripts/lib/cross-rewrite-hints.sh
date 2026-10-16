#!/usr/bin/env bash
# The commands scripts/cross-rewrite.sh prints in its refusals (D62, D63): the
# checkout of a store that is absent, and the run of record-rewrite.sh that
# publishes or rebuilds a rewrite record. Sourced by that script, which sets
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
# the origin of the repository $1; $2=--rebuild adds that flag. The commit-map
# is the one filter-repo wrote in the rewritten mirror, which only that mirror
# has. Args: $1=repo, $2=optional flag.
record_command() {
  local flag=""
  [ -z "${2:-}" ] || flag=" $2"
  # shellcheck disable=SC2016 # $MIRROR stays literal: the reader sets it
  printf '"%s/record-rewrite.sh"%s "$MIRROR" "$MIRROR/filter-repo/commit-map" %q' "$script_dir" "$flag" "$(origin_url "$1")"
}

# Prints the step that rebuilds the damaged record at the origin of the
# repository $1 in place, keeping every readable line of it.
# Args: $1=repo.
rebuild_steps() {
  # shellcheck disable=SC2016 # $MIRROR stays literal: the reader sets it
  printf 'Rebuild the record of %s from the rewrite'"'"'s commit-map, which only the rewritten mirror has (filter-repo leaves it as filter-repo/commit-map in the mirror). With MIRROR set to the mirror'"'"'s path, run this, which keeps every readable line of the record and replaces it in one push, then run this again:\n  %s' "$1" "$(record_command "$1" --rebuild)"
}
