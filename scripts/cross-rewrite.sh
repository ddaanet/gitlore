#!/usr/bin/env bash
# Usage: scripts/cross-rewrite.sh <store>
#
# Crosses one store to the history its remote rewrote (D61, D62). Run by hand
# from the project root, after the rewrite published its record
# (scripts/record-rewrite.sh). <store> is a non-bare memory store or tier, as a
# path from the project root. Its HEAD, `live` and `main` move to the ids the
# record maps them to, following each id's chain to its end; HEAD is detached
# at its new id. Children cross before their parents: a memory store refuses
# while a mounted tier still sits on a recorded commit, and the refusal names
# the command that crosses that tier first. Once the refs have moved, the
# store's gitlink is staged in its parent repository: a tier in the memory
# store's index, the memory store in the project's.
#
# A child store's record is fetched once per run. Ids in the record are as long
# as the store's object ids (40 hex digits for sha1, 64 for sha256).
#
# Every check runs before anything moves, so one refusal moves nothing. A
# refusal prints `cross-rewrite:` and its cause on stderr and exits 1. When
# every ref is already on the remote's history, the store is left alone and
# the script prints `nothing to cross` and exits 0. Status, diff and listing
# output is NUL-delimited, so a path with a space or a tab is compared as it is.
set -euo pipefail
unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture

# The crossing: checks, then the moves.
main() {
  # An absolute store, so every command a refusal prints runs from any directory.
  if [ -d "$store" ]; then
    store=$(cd "$store" && pwd -P)
  fi
  [ -e "$store/.git" ] || refuse "$store is not a checked-out store, so there is nothing to cross. Check it out with: $(checkout_command "$store")"
  set_id_length
  tmpd=$(mktemp -d "${TMPDIR:-/tmp}/cross-rewrite.XXXXXX")
  trap 'rm -rf "$tmpd"' EXIT

  check_clean
  fetch_store
  read_record "$store" "$tmpd/map"

  # Plan every ref before any moves. A ref that is absent is already crossed.
  head_old=$(git -C "$store" rev-parse HEAD)
  live_old=$(git -C "$store" rev-parse -q --verify refs/heads/live || true)
  main_old=$(git -C "$store" rev-parse -q --verify refs/heads/main || true)
  classify_ref HEAD "$head_old"
  head_new=$PLAN_NEW
  live_new=crossed
  if [ -n "$live_old" ]; then
    classify_ref live "$live_old"
    live_new=$PLAN_NEW
  fi
  main_new=crossed
  if [ -n "$main_old" ]; then
    classify_ref main "$main_old"
    main_new=$PLAN_NEW
  fi
  check_children "$head_old"

  if [ "$head_new" = crossed ] && [ "$live_new" = crossed ] && [ "$main_new" = crossed ]; then
    echo "cross-rewrite: nothing to cross in $store: its refs are on the remote's history."
    exit 0
  fi

  head_final=$head_new
  if [ "$head_new" = crossed ]; then
    head_final=$head_old
  fi
  # The checkout goes first: it is the step that can fail on the worktree, and
  # detaching HEAD frees the branch the ref updates below may move.
  git -C "$store" checkout -q --detach "$head_final"
  if [ "$live_new" != crossed ]; then
    git -C "$store" update-ref refs/heads/live "$live_new" "$live_old"
  fi
  if [ "$main_new" != crossed ]; then
    git -C "$store" update-ref refs/heads/main "$main_new" "$main_old"
  fi

  echo "cross-rewrite: crossed $store."
  echo "  HEAD ${head_old:0:7} -> ${head_final:0:7}, detached"
  if [ "$live_new" != crossed ]; then
    echo "  live ${live_old:0:7} -> ${live_new:0:7}"
  fi
  if [ "$main_new" != crossed ]; then
    echo "  main ${main_old:0:7} -> ${main_new:0:7}"
  fi
  stage_in_parent
}

# Every refusal names its cause; the script has moved nothing when it runs.
refuse() {
  printf 'cross-rewrite: %s\n' "$1" >&2
  exit 1
}

# Sets IDLEN, the hex length of the store's object ids (40 for sha1, 64 for
# sha256), and ZEROS, the id a dropped commit maps to. A record's lines are
# read with the store's length; a mounted child has the same object format.
set_id_length() {
  local format
  format=$(git -C "$store" rev-parse --show-object-format)
  case "$format" in
    sha1) IDLEN=40 ;;
    sha256) IDLEN=64 ;;
    *) refuse "$store reports the object format '$format', which has no known id length." ;;
  esac
  ZEROS=$(printf '%0*d' "$IDLEN" 0)
}

# Refuses unless every status entry is a gitlink staged in the index. A tier
# staged by an earlier crossing is the only change allowed; anything else,
# staged or not, is uncommitted work the crossing must not touch.
check_clean() {
  local entry out
  git -C "$store" status --porcelain -z > "$tmpd/status"
  while IFS= read -r -d '' entry; do
    out=""
    if [ "${entry:0:3}" = "M  " ]; then
      out=$(git -C "$store" --literal-pathspecs ls-files -s -- "${entry:3}")
    fi
    case "$out" in
      "160000 "*) ;;
      *) refuse "$store has uncommitted changes ($entry), so nothing was fetched. Commit, stash or unstage them, then run this again." ;;
    esac
  done < "$tmpd/status"
}

# Fetches the record and the remote's live, by explicit refspec only, so no
# archive branch reaches the store. A remote with no record has nothing to
# cross from.
fetch_store() {
  local err
  if ! err=$(git -C "$store" fetch -q --no-write-fetch-head origin +refs/heads/gitlore/rewrites:refs/gitlore/rewrites +refs/heads/live:refs/remotes/origin/live 2>&1); then
    case "$err" in
      *"couldn't find remote ref refs/heads/gitlore/rewrites"*)
        refuse "no rewrite record on the origin of $store, so there is nothing to cross. The record comes from the rewrite's commit-map, which only the rewritten mirror has (filter-repo leaves it as filter-repo/commit-map in the mirror). With MIRROR set to the mirror's path, publish it, then run this again:
  $(record_command "$store")" ;;
    esac
    refuse "could not fetch from the origin of $store. Once the remote is reachable, run this again. git said: $err"
  fi
}

# Fetches the remote's main, by explicit refspec, once: a mapped commit may be
# published there before `live` carries it. A remote without a main has nothing
# more to fetch, and its stale tracking ref is dropped.
fetch_main() {
  local err
  [ -z "$MAIN_FETCHED" ] || return 0
  MAIN_FETCHED=1
  if ! err=$(git -C "$store" fetch -q --no-write-fetch-head origin +refs/heads/main:refs/remotes/origin/main 2>&1); then
    case "$err" in
      *"couldn't find remote ref refs/heads/main"*)
        # The remote has no main, so a tracking ref left from an earlier fetch is stale.
        git -C "$store" update-ref -d refs/remotes/origin/main ;;
      *) refuse "could not fetch from the origin of $store. Once the remote is reachable, run this again. git said: $err" ;;
    esac
  fi
}

# Writes the map of the record fetched into $1's refs/gitlore/rewrites to $2,
# after checking the record's version. Args: $1=repo, $2=output file.
read_record() {
  local repo="$1" out="$2" version map_err
  if ! version=$(git -C "$repo" show refs/gitlore/rewrites:version 2>&1); then
    refuse "the rewrite record of $repo has no readable version file. git said: $version. $(rebuild_steps "$repo")"
  fi
  # The record is remote content and its ids reach printed commands, so
  # neither the version nor a bad line is echoed back.
  if [ "$version" != 1 ]; then
    # A bare integer above 1 is a newer format. Anything else is a damaged file.
    if [[ $version =~ ^[1-9][0-9]*$ ]]; then
      refuse "the rewrite record gitlore/rewrites of $repo is not version 1, the only version this script reads. Update gitlore, then run this again."
    fi
    refuse "the rewrite record gitlore/rewrites of $repo has a version file that is not a version number. $(rebuild_steps "$repo")"
  fi
  if ! map_err=$(git -C "$repo" show refs/gitlore/rewrites:map 2>&1 >"$out"); then
    refuse "the rewrite record of $repo has no readable map. git said: $map_err. $(rebuild_steps "$repo")"
  fi
  if grep -Evq "^[0-9a-f]{$IDLEN} [0-9a-f]{$IDLEN}\$" "$out"; then
    refuse "the rewrite record gitlore/rewrites of $repo has a map line that is not two ${IDLEN}-hex ids, so it cannot be trusted. $(rebuild_steps "$repo")"
  fi
}

# Fetches the rewrite record of the store mounted at $store/$1 from that
# store's own origin, once per run, and sets CHILD_MAP to a file holding its
# map. A record the remote lacks is an empty map: nothing was rewritten there,
# so its gitlinks are unchanged. Args: $1=child path within the store.
load_child_record() {
  local path="$1" child="$store/$1" err i=0
  while [ "$i" -lt "$CHILD_N" ]; do
    if [ "${CHILD_PATHS[$i]}" = "$path" ]; then
      CHILD_MAP="$tmpd/child.$i.map"
      return 0
    fi
    i=$((i + 1))
  done
  [ -e "$child/.git" ] || refuse "$child is not checked out, so its rewrite record cannot be read. Check it out with: git -C $(dq "$store") submodule update --init -- $(dq "$path")"
  CHILD_MAP="$tmpd/child.$CHILD_N.map"
  if ! err=$(git -C "$child" fetch -q --no-write-fetch-head origin +refs/heads/gitlore/rewrites:refs/gitlore/rewrites 2>&1); then
    case "$err" in
      *"couldn't find remote ref refs/heads/gitlore/rewrites"*)
        : > "$CHILD_MAP" ;;
      *)
        refuse "could not fetch gitlore/rewrites, the rewrite record of $child, from its origin, so its gitlinks cannot be checked. Once the remote is reachable, run this again. git said: $err" ;;
    esac
  else
    read_record "$child" "$CHILD_MAP"
  fi
  CHILD_PATHS[CHILD_N]="$path"
  CHILD_N=$((CHILD_N + 1))
}

# Prints the new id the map file $1 gives for the id $2, or nothing when the
# map has no line for $2.
map_next() {
  awk -v key="$2" '$1 == key { print $2; exit }' "$1"
}

# Sets CHAIN_END to where the id $2 ends in the map file $1: the id itself
# when no line maps it, otherwise the last id of its chain, which is ZEROS
# when the chain ends in a drop. A chain is followed at most one step per line.
# Args: $1=map file, $2=id, $3=the repository whose record the map is.
chain_end() {
  local map="$1" cur="$2" repo="$3" next lines steps=0
  lines=$(awk 'NF { n++ } END { print n + 0 }' "$map")
  next=$(map_next "$map" "$cur")
  while [ -n "$next" ]; do
    cur="$next"
    [ "$cur" != "$ZEROS" ] || break
    steps=$((steps + 1))
    [ "$steps" -le "$lines" ] || refuse "the rewrite record's chain from $2 does not end, so nothing was moved. $(rebuild_steps "$repo")"
    next=$(map_next "$map" "$cur")
  done
  CHAIN_END="$cur"
}

# Refuses unless the new commit $3 has the old commit $2's trees, except for
# gitlinks, and each gitlink of $2 maps to its counterpart in $3 through the
# record of the store mounted there. Args: $1=ref name, $2=old commit, $3=new commit.
check_commit() {
  local name="$1" old="$2" new="$3" old_tree new_tree meta path mismatch
  local om nm st rec head _mode kind sha ns
  old_tree=$(git -C "$store" rev-parse "$old^{tree}")
  if ! new_tree=$(git -C "$store" rev-parse -q --verify "$new^{tree}"); then
    fetch_main
    new_tree=$(git -C "$store" rev-parse -q --verify "$new^{tree}") \
      || refuse "$name of $store is at ${old:0:7}, which maps to ${new:0:7}, a commit this clone does not have, and neither the remote's live nor its main holds it: the rewritten history has not reached the remote yet. Nothing was moved. Once the rewrite's force-push has landed, run this again; it fetches the remote's live and main itself."
  fi
  git -C "$store" diff-tree -r -z --no-renames "$old_tree" "$new_tree" > "$tmpd/diff"
  mismatch=""
  while IFS= read -r -d '' -u 3 meta; do
    IFS= read -r -d '' -u 3 path
    read -r om nm _ _ st <<< "${meta#:}"
    # A gitlink changed in place is checked below; any other difference is not.
    if [ "$om" != 160000 ] || [ "$nm" != 160000 ] || [ "$st" != M ]; then
      mismatch=1
    fi
  done 3< "$tmpd/diff"
  [ -z "$mismatch" ] || refuse "$name of $store: ${old:0:7} maps to ${new:0:7}, but their trees differ outside gitlinks. Nothing was moved. A person must decide whether this rewrite was meant to change them; this script crosses only a rewrite that keeps every tree. Inspect the difference with:
  git -C $(dq "$store") diff --stat $old $new"
  git -C "$store" ls-tree -r -z --full-tree "$old_tree" > "$tmpd/links"
  while IFS= read -r -d '' -u 3 rec; do
    head=${rec%%$'\t'*}
    path=${rec#*$'\t'}
    read -r _mode kind sha <<< "$head"
    [ "$kind" = commit ] || continue
    ns=$(git -C "$store" rev-parse "$new_tree:$path")
    check_gitlink "$name" "$old" "$new" "$path" "$sha" "$ns"
  done 3< "$tmpd/links"
}

# Refuses unless the gitlink $4 of the store, which was $5 in the old commit
# and is $6 in the new one, maps through its own child's record. Args: $1=ref
# name, $2=old commit, $3=new commit, $4=child path, $5=old gitlink, $6=new gitlink.
check_gitlink() {
  local name="$1" old="$2" new="$3" path="$4" was="$5" now="$6" child
  child="$store/$path"
  load_child_record "$path"
  chain_end "$CHILD_MAP" "$was" "$child"
  if [ "$CHAIN_END" != "$now" ]; then
    refuse "$name of $store: ${old:0:7} maps to ${new:0:7}, but its gitlink $path (${was:0:7}) maps to ${CHAIN_END:0:7} in the record of $child, not ${now:0:7}. Nothing was moved. A person must decide which of the two records is wrong. Inspect the pinned gitlinks with:
  git -C $(dq "$store") diff-tree -r --no-renames $old $new"
  fi
}

# Refuses while a mounted tier, a gitlink checked out under the store, has a
# HEAD that its own record still maps: that tier crosses first.
# Args: $1=store commit whose gitlinks are the children.
check_children() {
  local commit="$1" rec head path _mode kind child child_head
  git -C "$store" ls-tree -r -z --full-tree "$commit" > "$tmpd/links"
  while IFS= read -r -d '' -u 3 rec; do
    head=${rec%%$'\t'*}
    path=${rec#*$'\t'}
    read -r _mode kind _ <<< "$head"
    [ "$kind" = commit ] || continue
    child="$store/$path"
    [ -e "$child/.git" ] || continue
    child_head=$(git -C "$child" rev-parse HEAD)
    load_child_record "$path"
    if [ -n "$(map_next "$CHILD_MAP" "$child_head")" ]; then
      refuse "tier $child is still on recorded commit ${child_head:0:7}, so $store cannot cross yet. Cross the tier first: $(dq "$script_dir/cross-rewrite.sh") $(dq "$child")"
    fi
  done 3< "$tmpd/links"
}

# Sets PLAN_NEW to where the ref $1, at commit $2, moves to, or to `crossed`
# when the commit is already on the remote's history. Refuses on any other case.
classify_ref() {
  local name="$1" sha="$2" base base_new target move
  if [ -n "$(map_next "$tmpd/map" "$sha")" ]; then
    chain_end "$tmpd/map" "$sha" "$store"
    target="$CHAIN_END"
    if [ "$target" = "$ZEROS" ]; then
      refuse_dropped "$name" "$sha" "$sha"
    fi
    # check_commit follows child records, which overwrite CHAIN_END: keep target.
    check_commit "$name" "$sha" "$target"
    PLAN_NEW="$target"
    return 0
  fi
  if git -C "$store" merge-base --is-ancestor "$sha" refs/remotes/origin/live; then
    PLAN_NEW=crossed
    return 0
  fi
  # The newest recorded commit on the first-parent line under $sha is the base.
  git -C "$store" rev-list --first-parent "$sha" > "$tmpd/ancestors"
  base=$(awk 'FILENAME == ARGV[1] { if (NF) keys[$1] = 1; next } ($1 in keys) { print; exit }' "$tmpd/map" "$tmpd/ancestors")
  if [ -n "$base" ]; then
    chain_end "$tmpd/map" "$base" "$store"
    base_new="$CHAIN_END"
    if [ "$base_new" = "$ZEROS" ]; then
      refuse_dropped "$name" "$sha" "$base"
    fi
    move=""
    [ "$name" = HEAD ] || move="
  git -C $(dq "$store") update-ref refs/heads/$name HEAD"
    refuse "$name of $store has local commits on top of $base, a recorded commit that maps to $base_new. Nothing was moved. Replay them onto the new history, then run this again:
  git -C $(dq "$store") checkout --detach $base_new
  git -C $(dq "$store") cherry-pick $base..$sha$move"
  fi
  # No recorded commit under it but history shared with the remote: local
  # commits on the new history, which a crossing has nothing to do for.
  if git -C "$store" merge-base "$sha" refs/remotes/origin/live >/dev/null; then
    PLAN_NEW=crossed
    return 0
  fi
  refuse "$name of $store is at ${sha:0:7}, which is neither on the remote's history nor on a recorded commit. Nothing was moved. A person must decide what becomes of its commits. Inspect them against the remote with:
  git -C $(dq "$store") log --oneline --graph $sha refs/remotes/origin/live"
}

# Stages the store's gitlink in its parent repository, when it has one.
stage_in_parent() {
  local parent abs rel
  parent=$(git -C "$store" rev-parse --show-superproject-working-tree)
  [ -n "$parent" ] || return 0
  parent=$(cd "$parent" && pwd -P)
  abs=$(cd "$store" && pwd -P)
  rel="${abs#"$parent"/}"
  git -C "$parent" add -- "$rel"
  echo "cross-rewrite: staged $rel in $parent."
}

if [ $# -ne 1 ]; then
  echo "usage: cross-rewrite.sh <store>" >&2
  exit 2
fi
store="$1"
script_dir=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck disable=SC1091 # linted as a file of its own
source "$script_dir/lib/cross-rewrite-hints.sh"
IDLEN=""
ZEROS=""
CHILD_PATHS=()
CHILD_N=0
MAIN_FETCHED=""
CHILD_MAP=""
CHAIN_END=""
PLAN_NEW=""
main
