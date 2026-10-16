#!/usr/bin/env bash
# Usage: scripts/record-rewrite.sh <store> <commit-map> [<remote>]
#
# Appends the changed lines of a `git filter-repo` commit-map to the append-only
# `gitlore/rewrites` record on the store's remote (D61): `origin` unless a third
# argument names another remote or gives a URL. <store> is any git repository,
# bare or not. Run by hand after filter-repo has rewritten the store and before
# the force-push of `live`. filter-repo leaves a bare mirror with no `origin`, so
# that run passes the remote's URL. The old tip goes to its own
# gitlore/archive/<date> branch, pushed separately: this script pushes only the
# record and never touches an archive branch.
#
# The record is a chain of commits, each holding `version` (1) and `map`
# (`<old> <new>` lines, ids as long as the store's object ids: 40 hex digits
# for sha1, 64 for sha256). New lines go on top of the remote's tip, and the
# push is plain, so the remote refuses anything that is not a fast-forward. A
# line the record already holds byte for byte is skipped. An old id the record maps to a
# different new id is refused: that is a second rewrite of the same history, from
# another mirror, and nothing is recorded for it.
#
# The commit is built with plumbing (hash-object, mktree, commit-tree). The store's
# branches, HEAD, index and worktree are left alone. Exit 0 when the record holds
# every changed line, whether added now or already there. Exit 1 with a
# `record-rewrite:` message on stderr when nothing was pushed. Exit 2 on usage.
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "usage: record-rewrite.sh <store> <commit-map> [<remote>]" >&2
  exit 2
fi
store="$1"
map_in="$2"
remote="${3:-origin}"

# Every refusal names its cause and says nothing was pushed.
refuse() {
  printf 'record-rewrite: %s Nothing was pushed.\n' "$1" >&2
  exit 1
}

[ -f "$map_in" ] || refuse "there is no commit-map at $map_in."
if ! gitdir_err=$(git -C "$store" rev-parse --git-dir 2>&1); then
  refuse "$store is not a git repository: $(printf '%s' "$gitdir_err" | tr '\n' ' ')"
fi
# The ids of a record are as long as the store's object ids: 40 hex digits for
# sha1, 64 for sha256.
if ! format=$(git -C "$store" rev-parse --show-object-format 2>&1); then
  refuse "could not read the object format of $store: $(printf '%s' "$format" | tr '\n' ' ')"
fi
case "$format" in
  sha1) idlen=40 ;;
  sha256) idlen=64 ;;
  *) refuse "$store has an object format this script does not know." ;;
esac
# Only the default is checked by name: an explicit remote is a name git resolves
# or a URL it reads, and either failing is git's own message below.
if [ $# -eq 2 ] && [ -z "$(git -C "$store" config --get remote.origin.url)" ]; then
  refuse "$store has no remote named origin, so there is no record to append to. Pass the remote's URL as the third argument."
fi

tmpd=$(mktemp -d "${TMPDIR:-/tmp}/record-rewrite.XXXXXX")
trap 'rm -rf "$tmpd"' EXIT

# Every line must be a pair of ids, except filter-repo's own header on the
# first line. One bad line refuses the whole map: a partial record would look
# complete.
hex_pair="^[0-9a-f]{$idlen} [0-9a-f]{$idlen}\$"
header='^old[[:space:]]+new[[:space:]]*$'
changed="$tmpd/changed"
: > "$changed"
lineno=0
line=""
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  if [ "$lineno" -eq 1 ] && [[ $line =~ $header ]]; then
    continue
  fi
  [[ $line =~ $hex_pair ]] \
    || refuse "commit-map line $lineno is not an '<old> <new>' pair of ${idlen}-hex ids: $line"
  # Unchanged commits have no line in the record; the rest keep their order.
  if [ "${line%% *}" != "${line#* }" ]; then
    printf '%s\n' "$line" >> "$changed"
  fi
done < "$map_in"
[ -s "$changed" ] || refuse "the commit-map has no changed lines, so there is nothing to record."

# A scratch ref is cleared first, so an absent remote record cannot leave an old
# one standing. The record is fetched by explicit refspec: no other branch comes
# with it, and --no-write-fetch-head leaves FETCH_HEAD alone.
git -C "$store" update-ref -d refs/gitlore/rewrites
if ! fetch_err=$(git -C "$store" fetch -q --no-write-fetch-head "$remote" +refs/heads/gitlore/rewrites:refs/gitlore/rewrites 2>&1); then
  case "$fetch_err" in
    *"couldn't find remote ref"*) ;;
    *) refuse "could not fetch gitlore/rewrites from $remote, so the record cannot be checked: $(printf '%s' "$fetch_err" | tr '\n' ' ')" ;;
  esac
fi

tip=""
: > "$tmpd/record"
if git -C "$store" rev-parse -q --verify refs/gitlore/rewrites >/dev/null; then
  tip=$(git -C "$store" rev-parse refs/gitlore/rewrites)
  if ! version=$(git -C "$store" show "$tip:version" 2>&1); then
    refuse "the record on $remote has no readable version file: $(printf '%s' "$version" | tr '\n' ' ')"
  fi
  [ "$version" = "1" ] || refuse "the record on $remote is not version 1, the only version this script writes."
  if ! git -C "$store" show "$tip:map" > "$tmpd/record" 2>"$tmpd/err"; then
    refuse "the record on $remote has no readable map: $(tr '\n' ' ' < "$tmpd/err")"
  fi
  # Remote content: a bad line is refused, never echoed.
  ! grep -Evq "$hex_pair" "$tmpd/record" \
    || refuse "the record on $remote has a map line that is not two ${idlen}-hex ids, so it cannot be appended to."
  [ -z "$(tail -c 1 "$tmpd/record")" ] \
    || refuse "the record's map does not end in a newline, so appending would join lines."
fi

# Changed lines the record lacks, in commit-map order. A line whose old id is
# recorded with another new id is a conflict, and the whole record is refused.
awk 'FILENAME == ARGV[1] { have[$0] = 1; mapto[$1] = $2; next }
  !($0 in have) && ($1 in mapto) { print "conflict " $1 " " mapto[$1] " " $2; exit }
  !($0 in have) { print }' "$tmpd/record" "$changed" > "$tmpd/added"
conflict=$(grep '^conflict ' "$tmpd/added" || true)
if [ -n "$conflict" ]; then
  read -r _ old recorded proposed <<< "$conflict"
  refuse "gitlore/rewrites already maps $old to $recorded, not to $proposed. That is a second rewrite of the same history, from another mirror."
fi
if [ ! -s "$tmpd/added" ]; then
  echo "record-rewrite: gitlore/rewrites on $remote already holds every changed line; nothing to add."
  exit 0
fi

cat "$tmpd/record" "$tmpd/added" > "$tmpd/map"
mblob=$(git -C "$store" hash-object -w "$tmpd/map")
vblob=$(printf '1\n' | git -C "$store" hash-object -w --stdin)
tree=$(printf '100644 blob %s\tmap\n100644 blob %s\tversion\n' "$mblob" "$vblob" | git -C "$store" mktree)
count=$(awk 'END { print NR }' "$tmpd/added")
msg="record rewrite: $count changed lines"
if [ -n "$tip" ]; then
  commit=$(git -C "$store" commit-tree "$tree" -p "$tip" -m "$msg")
else
  commit=$(git -C "$store" commit-tree "$tree" -m "$msg")
fi

# Plain push, never forced: a remote tip that moved since the fetch is refused.
if ! push_err=$(git -C "$store" push -q "$remote" "$commit:refs/heads/gitlore/rewrites" 2>&1); then
  refuse "$remote refused the record: $(printf '%s' "$push_err" | tr '\n' ' ')"
fi
echo "record-rewrite: recorded $count changed lines on $remote gitlore/rewrites."
