#!/usr/bin/env bash
# Fixtures for the history-rewrite record (D61/D62). A store whose remote's
# `live` was rewritten without git-filter-repo: same trees, new committer, so
# every commit after the shared prefix P gets a new id.
#
#   remote live (before):  P - O1 - O2
#   remote live (after):   P - N1 - N2        (force-pushed)
#   remote gitlore/rewrites: version=1, map = "O1 N1" / "O2 N2"
#   remote gitlore/archive/2026-10-15: O2
#
# Caller runs setup_tmp_repo and make_parent_with_memory (and mount_tier_at_live
# for a tier) first. Globals set by rewrite_remote_history: RW_P RW_O1 RW_O2
# RW_N1 RW_N2, and RW_LOCAL (the store's local-only commit) once the clone is
# positioned.

# Rewrite $2's `live` and publish the record. Leaves $1 untouched except for
# the objects it fetches (the old commits), so a caller positions the clone
# afterwards with rewrite_position_clone.
# Args: $1=store path  $2=its bare remote
rewrite_remote_history() {
  local store="$1" bare="$2" work
  git -C "$store" push -q origin live || true
  work=$(mktemp -d "${TMP_REPO}/rewrite-work.XXXXXX") || return 1
  git clone -q "$bare" "$work" || return 1
  RW_P=$(git -C "$work" rev-parse origin/live)
  git -C "$work" checkout -q -B live origin/live
  (
    cd "$work" || exit 1
    git config user.email old@t; git config user.name old
    echo o1 > "rw-o1.md"; git add -A; git commit -qm "old one"
    echo o2 > "rw-o2.md"; git add -A; git commit -qm "old two"
  ) || return 1
  RW_O2=$(git -C "$work" rev-parse HEAD)
  RW_O1=$(git -C "$work" rev-parse HEAD^)
  # The old history goes to the archive branch, then the clone under test gets
  # the objects while the old tip is still a local ref in the scratch clone.
  git -C "$work" branch old-tip "$RW_O2"
  git -C "$store" fetch -q "$work" "refs/heads/old-tip:refs/gitlore-fixture/old-tip" || return 1
  RW_N1=$(rewrite_recommit "$work" "$RW_O1" "$RW_P") || return 1
  RW_N2=$(rewrite_recommit "$work" "$RW_O2" "$RW_N1") || return 1
  git -C "$work" push -q origin "$RW_O2:refs/heads/gitlore/archive/2026-10-15" || return 1
  git -C "$work" push -q -f origin "$RW_N2:refs/heads/live" || return 1
  rewrite_publish_record "$work" "$RW_O1 $RW_N1
$RW_O2 $RW_N2" || return 1
  rm -rf "$work"
  export RW_P RW_O1 RW_O2 RW_N1 RW_N2
}

# Same tree as $2, parent $3, a different author and committer.
# Args: $1=repo  $2=old commit  $3=new parent
rewrite_recommit() {
  GIT_AUTHOR_NAME=rewritten GIT_AUTHOR_EMAIL=new@t \
  GIT_COMMITTER_NAME=rewritten GIT_COMMITTER_EMAIL=new@t \
    git -C "$1" commit-tree "$2^{tree}" -p "$3" -m "$(git -C "$1" log -1 --format=%s "$2")"
}

# Push `gitlore/rewrites` holding the given version (default 1) and map text.
# Args: $1=scratch clone with origin set  $2=map text (no trailing newline)
#       $3=version file content (default 1)
rewrite_publish_record() {
  local work="$1" map="$2" vblob mblob tree commit
  vblob=$(printf '%s\n' "${3:-1}" | git -C "$work" hash-object -w --stdin) || return 1
  mblob=$(printf '%s\n' "$map" | git -C "$work" hash-object -w --stdin) || return 1
  tree=$(printf '100644 blob %s\tmap\n100644 blob %s\tversion\n' "$mblob" "$vblob" \
    | git -C "$work" mktree) || return 1
  commit=$(git -C "$work" -c user.email=t@t -c user.name=t \
    commit-tree "$tree" -m "record rewrite") || return 1
  git -C "$work" push -q origin "$commit:refs/heads/gitlore/rewrites"
}

# Put the store's HEAD and `live` on a local-only commit. "old" builds it on the
# old tip O2 (a clone that never crossed); "fresh" builds it on the shared
# prefix P (nothing recorded under it). Same shape either way, so a refusal
# cannot come from anything but the mapped old id.
# Args: $1=store path  $2=old|fresh
rewrite_position_clone() {
  local store="$1" mode="$2" base
  case "$mode" in
    old) base="$RW_O2" ;;
    fresh) base="$RW_P" ;;
    *) echo "rewrite_position_clone: unknown mode $mode" >&2; return 1 ;;
  esac
  # In "fresh" mode the old objects O1/O2 and refs/gitlore-fixture/old-tip stay
  # in the clone on purpose: they catch a green that tests whether a map key
  # exists locally (cat-file -e) or walks --all instead of authority..pending.
  git -C "$store" checkout -q --detach "$base" || return 1
  echo local > "$store/rw-local.md"
  git -C "$store" add rw-local.md
  git -C "$store" -c user.email=t@t -c user.name=t commit -q -m "Local commit" || return 1
  git -C "$store" update-ref refs/heads/live HEAD
  RW_LOCAL=$(git -C "$store" rev-parse HEAD)
  git -C "$store" fetch -q origin live
  export RW_LOCAL
}

# Replace the published record with one whose `map` blob the remote lacks: the
# ref, commit and tree exist, so the ref advertises, but fetching it fails.
# Args: $1=bare remote
rewrite_break_record() {
  local bare="$1" mblob vblob tree commit loose
  mblob=$(printf 'unfetchable map\n' | git -C "$bare" hash-object -w --stdin) || return 1
  vblob=$(printf '1\n' | git -C "$bare" hash-object -w --stdin) || return 1
  tree=$(printf '100644 blob %s\tmap\n100644 blob %s\tversion\n' "$mblob" "$vblob" \
    | git -C "$bare" mktree) || return 1
  commit=$(git -C "$bare" -c user.email=t@t -c user.name=t commit-tree "$tree" -m "broken record") || return 1
  git -C "$bare" update-ref refs/heads/gitlore/rewrites "$commit" || return 1
  loose="$bare/objects/${mblob:0:2}/${mblob:2}"
  [ -f "$loose" ] || { echo "rewrite_break_record: blob not loose" >&2; return 1; }
  rm -f "$loose"
}

# Assert a refused yield left nothing to continue: no state file, no
# MERGE_HEAD, HEAD and live where they were.
# Args: $1=store  $2=HEAD before  $3=live before
assert_yield_left_nothing() {
  local store="$1" head="$2" live="$3"
  [ ! -e "$(git -C "$store" rev-parse --git-path gitlore-merge-state)" ] || { echo "state file left" >&2; return 1; }
  if git -C "$store" rev-parse -q --verify MERGE_HEAD >/dev/null; then echo "MERGE_HEAD left" >&2; return 1; fi
  [ "$(git -C "$store" rev-parse HEAD)" = "$head" ] || { echo "HEAD moved" >&2; return 1; }
  [ "$(git -C "$store" rev-parse live)" = "$live" ] || { echo "live moved" >&2; return 1; }
}

# True when no ref in the store — under any name — is the archive branch: none
# points at the archive tip $RW_O2 except the fixture's own transfer ref, and
# none is named like one. Any namespace, since a record fetch by wildcard
# refspec (or with --refmap=) lands outside refs/remotes/origin/.
assert_no_archive_fetched() {
  local hits
  hits=$(git -C "$1" for-each-ref --format='%(refname)' --points-at "$RW_O2" \
    | grep -v '^refs/gitlore-fixture/' || true)
  hits="$hits$(git -C "$1" for-each-ref --format='%(refname)' | grep '/archive/' || true)"
  [ -z "$hits" ] || { echo "archive branch fetched: $hits" >&2; return 1; }
}

# Write a filter-repo style commit-map: the header, then one `old new` line per
# argument. An unchanged commit has old == new; a dropped one maps to 40 zeros.
# Args: $1=file  $2...=lines
rewrite_write_commit_map() {
  local file="$1"
  shift
  {
    printf 'old                                      new\n'
    printf '%s\n' "$@"
  } > "$file"
}

# Everything a script must leave alone in a store: HEAD, branches, the index
# tree, and the worktree status.
# Args: $1=store
rewrite_store_snapshot() {
  git -C "$1" rev-parse HEAD
  git -C "$1" for-each-ref refs/heads
  git -C "$1" write-tree
  git -C "$1" status --porcelain
}
