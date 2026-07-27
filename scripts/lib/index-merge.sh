#!/usr/bin/env bash
# Entry-wise three-way merge for index files (`MEMORY.md`). Source; do not exec.
# Depends on scripts/lib/index-compose.sh for gitlore_bullet_path,
# gitlore_index_part and gitlore_compose_pick — callers must source it first.
#
# An index is a LIST OF ENTRIES, not prose: each pointer bullet is an
# independent record keyed by its path. A line-wise merge reads it as prose and
# gets two things wrong that matter. Two sides inserting DIFFERENT facts at the
# same offset conflict textually although nothing is actually in dispute; two
# sides inserting the SAME path at different offsets do not conflict at all and
# produce a duplicate pointer — the state `gitlore_compose_check` refuses on, so
# a silent textual success is what strands the store.
#
# Keying on the path fixes both, and the presence rule is the one the root↔
# carrier compose already uses (D17): a path present at base survives only if
# BOTH sides still carry it (a delete on either side wins); a path new since
# base survives if EITHER side added it. Only a genuine disagreement about ONE
# path's text is left as a conflict, and it is emitted diff3-style so the base
# text is right there — which side edited is otherwise unknowable from two
# versions.
#
# Preamble and trailer are prose and merge as prose, through `git merge-file
# --diff3`.

# Print the pointer paths of $1's bullets, one per line, in file order.
gitlore_index_merge_paths() {
  local line path
  while IFS= read -r line; do
    path=$(gitlore_bullet_path "$line") || continue
    printf '%s\n' "$path"
  done < <(gitlore_index_part "$1" bullets)
}

# Split one side of the merge into the four working files the merge reads.
# A missing file is a legitimate side (the index did not exist at base), and
# splits to four empty ones. Args: $1 = tmpdir, $2 = side name, $3 = source file.
_gitlore_index_merge_split() {
  local tmpd="$1" side="$2" src="$3"
  if [ -f "$src" ]; then
    gitlore_index_part "$src" preamble > "$tmpd/$side.pre" || return 1
    gitlore_index_part "$src" trailer  > "$tmpd/$side.post" || return 1
    gitlore_index_part "$src" bullets  > "$tmpd/$side.bullets" || return 1
    gitlore_index_merge_paths "$src"   > "$tmpd/$side.paths" || return 1
  else
    : > "$tmpd/$side.pre" || return 1
    : > "$tmpd/$side.post" || return 1
    : > "$tmpd/$side.bullets" || return 1
    : > "$tmpd/$side.paths" || return 1
  fi
  return 0
}

# Emit the merged bullet block on stdout. Order is OURS order for every
# surviving path, then the paths only THEIRS has, in theirs order — the same
# rule `gitlore_compose_tier_bullets` uses, and the reason no insertion-point
# arithmetic is needed: for the root index composition reorders the tier blocks
# straight afterwards anyway, and for a carrier the incoming side's new facts
# belong at the end.
# Always returns 0; the caller detects conflicts from the emitted markers.
# Args: $1 = tmpdir, $2/$3/$4 = ours/base/theirs labels.
_gitlore_index_merge_bullets() {
  local tmpd="$1" olabel="$2" blabel="$3" tlabel="$4"
  local path seen="" b o t oline tline bline
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    printf '%s\n' "$seen" | grep -qxF -- "$path" && continue
    seen="$seen
$path"
    grep -qxF -- "$path" "$tmpd/base.paths"   && b=1 || b=0
    grep -qxF -- "$path" "$tmpd/ours.paths"   && o=1 || o=0
    grep -qxF -- "$path" "$tmpd/theirs.paths" && t=1 || t=0
    if [ "$b" = 1 ]; then
      { [ "$o" = 1 ] && [ "$t" = 1 ]; } || continue   # at base: a delete wins
    else
      { [ "$o" = 1 ] || [ "$t" = 1 ]; } || continue   # new since base: an add wins
    fi
    oline=$(gitlore_compose_pick "$path" < "$tmpd/ours.bullets")
    tline=$(gitlore_compose_pick "$path" < "$tmpd/theirs.bullets")
    bline=$(gitlore_compose_pick "$path" < "$tmpd/base.bullets")
    if [ "$o" = 0 ]; then printf '%s\n' "$tline"; continue; fi
    if [ "$t" = 0 ]; then printf '%s\n' "$oline"; continue; fi
    if [ "$oline" = "$tline" ]; then printf '%s\n' "$oline"; continue; fi
    if [ "$b" = 1 ] && [ "$oline" = "$bline" ]; then printf '%s\n' "$tline"; continue; fi
    if [ "$b" = 1 ] && [ "$tline" = "$bline" ]; then printf '%s\n' "$oline"; continue; fi
    # Both sides moved this one entry, and apart. The base line is carried into
    # the chunk even when the path is new to both sides (an empty base section),
    # so the shape the agent reads never changes with the case.
    printf '<<<<<<< %s\n%s\n||||||| %s\n' "$olabel" "$oline" "$blabel"
    [ "$b" = 1 ] && printf '%s\n' "$bline"
    printf '=======\n%s\n>>>>>>> %s\n' "$tline" "$tlabel"
  done <<EOF
$(cat "$tmpd/ours.paths" "$tmpd/theirs.paths")
EOF
  return 0
}

# Three-way merge one index file. Prints the merged content on stdout.
# Returns 0 when it merged clean, 1 when the output carries conflict markers,
# 2 when the merge could not be attempted at all.
# Args: $1/$2/$3 = base/ours/theirs files (a missing path is an empty side),
#       $4/$5/$6 = ours/base/theirs conflict labels.
gitlore_index_merge() {
  local basef="$1" oursf="$2" theirsf="$3"
  local olabel="${4:-MINE}" blabel="${5:-BASE}" tlabel="${6:-THEIRS}"
  local tmpd rc=0 mrc

  tmpd=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-index-merge.XXXXXX") || return 2
  # Every step is checked explicitly: this function is called from an `if` or
  # with `|| rc=$?`, and errexit is suspended for everything reached from there.
  _gitlore_index_merge_split "$tmpd" base   "$basef"   || { rm -rf "$tmpd"; return 2; }
  _gitlore_index_merge_split "$tmpd" ours   "$oursf"   || { rm -rf "$tmpd"; return 2; }
  _gitlore_index_merge_split "$tmpd" theirs "$theirsf" || { rm -rf "$tmpd"; return 2; }

  # A side that already names one path twice is not a list of entries — keying on
  # the path would collapse the pair and silently drop whichever line lost. That
  # index is malformed before the merge, and `gitlore_compose_check` is what
  # reports it; declining to merge leaves it intact for that check to find.
  local side
  for side in base ours theirs; do
    if [ -n "$(sort "$tmpd/$side.paths" | uniq -d)" ]; then rm -rf "$tmpd"; return 2; fi
  done

  # Prose halves, through git's own three-way. merge-file reports the CONFLICT
  # COUNT as its exit status, so any small non-zero is a conflict and only a
  # large one (git returns -1) is a failure to merge at all.
  local part
  for part in pre post; do
    mrc=0
    git merge-file -p --diff3 -L "$olabel" -L "$blabel" -L "$tlabel" \
      "$tmpd/ours.$part" "$tmpd/base.$part" "$tmpd/theirs.$part" \
      > "$tmpd/out.$part" || mrc=$?
    if [ "$mrc" -ge 128 ]; then rm -rf "$tmpd"; return 2; fi
    [ "$mrc" -gt 0 ] && rc=1
  done

  _gitlore_index_merge_bullets "$tmpd" "$olabel" "$blabel" "$tlabel" \
    > "$tmpd/out.bullets" || { rm -rf "$tmpd"; return 2; }
  grep -q '^<<<<<<< ' "$tmpd/out.bullets" && rc=1

  cat "$tmpd/out.pre" "$tmpd/out.bullets" "$tmpd/out.post" || { rm -rf "$tmpd"; return 2; }
  rm -rf "$tmpd"
  return "$rc"
}

# Print every tracked index file in $1's worktree that carries a conflict
# marker. The entry-wise merge resolves an index in the WORKTREE without
# staging it when it conflicts, so git's unmerged-entry list does not name it
# and the state file would otherwise send the sub-agent past a real conflict.
gitlore_conflicted_indexes() {
  local store="$1" name
  while IFS= read -r name; do
    case "$name" in MEMORY.md|*/MEMORY.md) ;; *) continue ;; esac
    [ -f "$store/$name" ] || continue
    grep -q '^<<<<<<< ' "$store/$name" && printf '%s\n' "$name"
  done < <(git -C "$store" ls-files | sort -u)
  # Finding nothing is the normal case, but it leaves the loop's status at the
  # last grep's 1. Callers run this in a `pipefail` pipeline, where that reads as
  # a failed producer.
  return 0
}

# Print every index path (`MEMORY.md`, at any depth) that any of the three
# commits carries, once each. A `ls-tree` failure speaks on stderr and
# contributes nothing — the caller then leaves git's own merge result standing,
# which is the safe direction.
# Args: $1 = store, $2/$3/$4 = base/ours/theirs commit-ish.
gitlore_index_paths_in() {
  local store="$1" ref name
  for ref in "$2" "$3" "$4"; do
    while IFS= read -r name; do
      case "$name" in
        MEMORY.md|*/MEMORY.md) printf '%s\n' "$name" ;;
      esac
    done < <(git -C "$store" ls-tree -r --name-only "$ref")
  done | sort -u
}

# Re-merge every index file in a prepared merge entry-wise, replacing whatever
# the line-wise merge left in the worktree. Prints the paths it left conflicted,
# one per line.
#
# Runs on EVERY index the merge touches, not only the ones git flagged: a
# duplicate pointer path is produced by a merge git considers CLEAN, so
# inspecting only the conflicted files is exactly how it slips through.
# Depends on gitlore_git (util.sh). Args: $1 = store, $2 = base sha,
# $3 = ours ref, $4 = theirs ref.
gitlore_merge_indexes() {
  local store="$1" base="$2" ours="$3" theirs="$4"
  local paths path tmpd rc side ref
  paths=$(gitlore_index_paths_in "$store" "$base" "$ours" "$theirs")
  [ -n "$paths" ] || return 0
  tmpd=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-merge-indexes.XXXXXX") || return 1
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    for side in base ours theirs; do
      case "$side" in
        base) ref="$base" ;; ours) ref="$ours" ;; *) ref="$theirs" ;;
      esac
      # A side that never had this index is an empty file, which the merge reads
      # as "nothing to have been deleted" — the union semantics a new index
      # wants. `-q --verify` is silent on that expected miss.
      if git -C "$store" rev-parse -q --verify "$ref:$path" >/dev/null; then
        git -C "$store" show "$ref:$path" > "$tmpd/$side" || : > "$tmpd/$side"
      else
        : > "$tmpd/$side"
      fi
    done
    rc=0
    gitlore_index_merge "$tmpd/base" "$tmpd/ours" "$tmpd/theirs" \
      "MINE ($ours)" "BASE" "THEIRS ($theirs)" > "$tmpd/merged" || rc=$?
    [ "$rc" -ge 2 ] && continue        # unmergeable: leave git's own result be
    cp "$tmpd/merged" "$store/$path" || continue
    if [ "$rc" -eq 0 ]; then
      gitlore_git -C "$store" add -- "$path" || true
    else
      printf '%s\n' "$path"
    fi
  done <<EOF
$paths
EOF
  rm -rf "$tmpd"
  return 0
}
