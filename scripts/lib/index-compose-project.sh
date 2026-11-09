#!/usr/bin/env bash
# Compose-project: the down projection into a tier's carrier and the root's
# composed bullet block — the per-index projection work gitlore_compose drives
# — and the three-way compose-up of a tier ahead of its pin, which the take, the
# memory merge's continuation and the recovery drive.
# Part of lib/index-compose.sh; source that, not this file.

# Print the root index's pointer paths at the memory store's HEAD, one per line.
# `-q --verify` is silent on the one expected miss: a store whose root index is
# not committed yet, which prints nothing.
gitlore_index_head_paths() {
  local mempath="$1" line
  git -C "$mempath" rev-parse -q --verify HEAD:MEMORY.md >/dev/null || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    gitlore_bullet_path "$line" || continue
  done < <(git -C "$mempath" show HEAD:MEMORY.md)
}

# Print tier $2's new carrier bullet list, unprefixed: root's lines for that tier,
# projected DOWN. Root is canonical (D17), so every line root carries is emitted
# with root's text and root's placement — this is where a line authored in the
# root index becomes a line the tier can travel with.
#
# Every tier the pass reaches sits on its pin (rule 7 refuses one ahead of it,
# and the take that moves a tier composes it up three-way before recording it),
# so root already holds what the carrier gained. What is left to decide is
# a carrier path root does not carry, and "root lacks it" alone is ambiguous —
# root may have deleted it, or may never have had it. Root at HEAD answers:
#
#   present there → root deleted the line → drop it from the carrier;
#   absent there  → nobody authored it in root → keep it (a line written straight
#                   into the carrier, or one left there while the tier slept),
#                   and gitlore_compose_orphans names it.
#
# The converse case is a path root still carries that the carrier lacks, with root
# at HEAD carrying it too: root made no deletion, so the carrier did, alone. Root
# is canonical, so the line is root's insertion at root's offset and is emitted
# with root's text — the carrier-side deletion is restored, whatever root at HEAD
# says about it. A removal starts in the root index.
#
# One lookup against a commit git already holds. Nothing is remembered between
# passes: a reconciliation ref would be state that can outlive what it describes,
# and the pin is what makes it unnecessary.
#
# Order is merged through gitlore_order_merge over the three path lists, so a
# kept carrier-only line stays at its own offset instead of collecting at the end.
gitlore_compose_down() {
  local mempath="$1" tier="$2"
  local carrier="$mempath/$tier/MEMORY.md"
  local root="$mempath/MEMORY.md"
  local line path tmpd b o t

  tmpd=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-compose-down.XXXXXX") || return 1
  local side
  for side in root carrier head; do
    : > "$tmpd/$side.paths" || { rm -rf "$tmpd"; return 1; }
    : > "$tmpd/$side.bullets" || { rm -rf "$tmpd"; return 1; }
  done

  # root — its bullets for this tier, prefix stripped: the canonical text and the
  # authored order.
  if [ -f "$root" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in "$tier"/*) ;; *) continue ;; esac
      line=$(gitlore_bullet_deprefix "$line" "$tier") || continue
      printf '%s\n' "$line" >> "$tmpd/root.bullets"
      printf '%s\n' "${path#"$tier"/}" >> "$tmpd/root.paths"
    done < "$root"
  fi

  # carrier — the working tree's bullets, in carrier order.
  if [ -f "$carrier" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      printf '%s\n' "$line" >> "$tmpd/carrier.bullets"
      printf '%s\n' "$path" >> "$tmpd/carrier.paths"
    done < <(gitlore_index_part "$carrier" bullets)
  fi

  # root at HEAD — paths only, and only this tier's. An uncommitted root index
  # leaves the list empty and makes every carrier line a keep.
  while IFS= read -r path; do
    case "$path" in "$tier"/*) ;; *) continue ;; esac
    printf '%s\n' "${path#"$tier"/}" >> "$tmpd/head.paths"
  done < <(gitlore_index_head_paths "$mempath")

  # A path root carries and the carrier lacks is root's insertion, whatever root
  # at HEAD says: only the carrier lost it, and root's deletion would have left
  # root without it. Dropped from the head list, the order merge sees it as new
  # in root and places it at root's offset.
  : > "$tmpd/head.kept" || { rm -rf "$tmpd"; return 1; }
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if grep -qxF -- "$path" "$tmpd/root.paths" && ! grep -qxF -- "$path" "$tmpd/carrier.paths"; then
      continue
    fi
    printf '%s\n' "$path" >> "$tmpd/head.kept"
  done < "$tmpd/head.paths"
  mv "$tmpd/head.kept" "$tmpd/head.paths" || { rm -rf "$tmpd"; return 1; }

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    grep -qxF -- "$path" "$tmpd/head.paths"    && b=1 || b=0
    grep -qxF -- "$path" "$tmpd/root.paths"    && o=1 || o=0
    grep -qxF -- "$path" "$tmpd/carrier.paths" && t=1 || t=0
    if [ "$o" = 1 ]; then
      gitlore_compose_pick "$path" < "$tmpd/root.bullets"
    elif [ "$t" = 1 ] && [ "$b" = 0 ]; then
      gitlore_compose_pick "$path" < "$tmpd/carrier.bullets"
    fi
  done < <(gitlore_order_merge "$tmpd/head.paths" "$tmpd/root.paths" "$tmpd/carrier.paths")

  rm -rf "$tmpd"
  return 0
}

# Print the root path of every line the next gitlore_compose_down restores: one
# the carrier of an active tier lost while root still carries it and root at HEAD
# carries it too. Read from the store before the pass, because the written
# result no longer shows the loss. Same tiers the pass projects into: active,
# carrier present, root holding a line for the tier.
gitlore_compose_restores() {
  local mempath="$1" tier line path head root
  root="$mempath/MEMORY.md"
  [ -f "$root" ] || return 0
  head=$(gitlore_index_head_paths "$mempath")
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    gitlore_index_has_tier "$root" "$tier" || continue
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in "$tier"/*) ;; *) continue ;; esac
      grep -qxF -- "$path" <<<"$head" || continue
      gitlore_index_has_path "$mempath/$tier/MEMORY.md" "${path#"$tier"/}" && continue
      printf '%s\n' "$path"
    done < <(gitlore_index_part "$root" bullets)
  done < <(gitlore_active_tiers "$mempath")
  return 0
}

# Return 0 when index $1 carries at least one pointer line prefixed with tier $2.
gitlore_index_has_tier() {
  local file="$1" tier="$2" line path
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    path=$(gitlore_bullet_path "$line") || continue
    case "$path" in "$tier"/*) return 0 ;; esac
  done < "$file"
  return 1
}

# Print the root index's composed bullet block: each ACTIVE tier's lines, in
# manifest order, then the project's own bare-path lines in the order they
# already have.
#
# A tier's lines are taken from ROOT, which is what keeps a pass over tiers on
# their pins placement-only — it moves lines, it never rewrites one. A tier with
# no carrier file, a registered tier with no checkout among them, always is:
# nothing else holds its lines. Two cases read something else:
#
#   - $2 names a directory gitlore_compose_merge_tiers filled and lists the tier
#     there: the tier's block is that three-way merge of root's lines with the
#     carrier, diff3 chunk included where both changed one entry apart.
#   - root carries no line at all for an active tier with a carrier. That is what
#     a freshly mounted or freshly activated tier looks like, and root has no
#     opinion about it yet, so it takes the carrier's — the augmentation a mount
#     owes the index. Deleting every one of a tier's lines from root therefore
#     brings the block back: the down projection skips a tier root has no line
#     for, so the carrier still holds them. Deactivating the tier is what drops
#     its block.
#
# Lines prefixed with a mounted but DORMANT tier are dropped: root does not
# represent a dormant tier. They keep living in its carrier, and reactivating the
# tier brings them back through the case above.
gitlore_compose_root_bullets() {
  local mempath="$1" merged="${2:-}"
  local root="$mempath/MEMORY.md" active tier line path n
  active=$(gitlore_active_tiers "$mempath")

  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    if [ -n "$merged" ] && n=$(gitlore_line_number "$tier" "$merged/tiers"); then
      cat -- "$merged/$n"
    elif [ -f "$mempath/$tier/MEMORY.md" ] && ! gitlore_index_has_tier "$root" "$tier"; then
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        gitlore_bullet_reprefix "$line" "$tier" || continue
      done < <(gitlore_index_part "$mempath/$tier/MEMORY.md" bullets)
    else
      while IFS= read -r line || [ -n "$line" ]; do
        path=$(gitlore_bullet_path "$line") || continue
        case "$path" in "$tier"/*) printf '%s\n' "$line" ;; esac
      done < <(gitlore_index_part "$root" bullets)
    fi
  done <<EOF
$active
EOF

  while IFS= read -r line || [ -n "$line" ]; do
    path=$(gitlore_bullet_path "$line") || continue
    case "$path" in */*) continue ;; esac
    printf '%s\n' "$line"
  done < <(gitlore_index_part "$root" bullets)
}

# Compose the tiers $2 lists, one per line, UP into the root index three-way and
# write it once; every other line stays where it is. $3 says where the base
# gitlink is read, as gitlore_compose_merge_tiers takes it; $4 is its optional
# mode, `tier-wins`, under which a line both sides changed takes the tier's
# instead of a chunk and is reported on stdout, one line per path. Its callers
# are the three paths that move a tier: the end of a take runs it for the tiers
# it left ahead of the memory index's gitlinks, the memory merge's continuation
# for the tiers ahead of the gitlinks OURS records, and the recovery for a tier
# merge that landed outside the continuation. The pass never calls it: rule 7
# refuses a tier ahead of its pin there, naming the take.
#
# Writes no carrier, so a merge in one store never propagates into another the
# user did not review. Returns 0, 1 and 2 as gitlore_compose does, and 3 when
# the write left a diff3 chunk in root, with the composed line and one line per
# marker on stdout; the merged tiers' gitlinks are then staged
# (gitlore_stage_merged_tiers).
gitlore_compose_up() {
  local mempath="$1" tiers="$2" at="$3" mode="${4-}"
  local root="$mempath/MEMORY.md" dir out rc=0
  [ -f "$root" ] || return 0
  if ! gitlore_compose_check "$mempath"; then
    return 1
  fi
  if ! dir=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-compose-up.XXXXXX"); then
    printf 'could not make a scratch directory to compose %s\n' "$root"
    return 2
  fi
  out=$(gitlore_compose_merge_tiers "$mempath" "$tiers" "$dir" "$at" "$mode") || rc=$?
  if [ "$rc" -ge 2 ]; then
    rm -rf "$dir"
    printf '%s\n' "$out"
    return 1
  fi
  if ! out=$(gitlore_compose_root_bullets "$mempath" "$dir" | gitlore_compose_write "$root"); then
    rm -rf "$dir"
    printf 'could not write %s\n' "$root"
    return 2
  fi
  [ -z "$out" ] || printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then
    [ ! -s "$dir/notes" ] || cat "$dir/notes"
    rm -rf "$dir"
    return 0
  fi
  if ! gitlore_stage_merged_tiers "$mempath" "$dir"; then
    rm -rf "$dir"
    return 2
  fi
  rm -rf "$dir"
  gitlore_index_marker_lines "$root"
  return 3
}

# Stage the gitlink of every tier gitlore_compose_merge_tiers listed in $2/tiers,
# once root holds a diff3 chunk for them. The staged gitlink is the base every
# later pass and commit reads, so this is how root records that it has seen the
# tier's version: a chunk resolved to either side, or to neither, then stands
# instead of being merged into the same chunk again. Commits nothing. Prints
# the tier it could not stage and returns 1.
gitlore_stage_merged_tiers() {
  local mempath="$1" dir="$2" tier abs
  while IFS= read -r tier || [ -n "$tier" ]; do
    [ -n "$tier" ] || continue
    if ! gitlore_git -C "$mempath" add -- "$tier" >&2; then
      abs=$(CDPATH='' cd -- "$mempath" && pwd) || abs="$mempath"
      # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
      printf 'could not stage the %s pointer; the root index is written. Run `git -C "%s" add -- "%s"`\n' "$tier" "$abs" "$tier"
      return 1
    fi
  done < "$dir/tiers"
  return 0
}

# Print each ACTIVE tier whose HEAD strictly descends the gitlink memory records
# for it at $2, one per line: `:` reads memory's index, `HEAD:` its HEAD, which
# the memory merge's continuation reads, since the prepared merge's index
# already holds each tier's HEAD. A pin the tier does not hold is not ahead of
# anything, and is left to the pin guard.
gitlore_tiers_off_pin() {
  local mempath="$1" at="$2" tier pin head
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    # `git -C` into an unchecked-out submodule walks up to the enclosing repo.
    [ -e "$mempath/$tier/.git" ] || continue
    # `-q --verify` is silent on the expected misses: no gitlink recorded there
    # (mid-mount), and a tier with no commit.
    pin=$(git -C "$mempath" rev-parse -q --verify "$at$tier") || continue
    head=$(git -C "$mempath/$tier" rev-parse -q --verify HEAD) || continue
    [ "$head" != "$pin" ] || continue
    git -C "$mempath/$tier" rev-parse -q --verify "${pin}^{commit}" >/dev/null || continue
    git -C "$mempath/$tier" merge-base --is-ancestor "$pin" "$head" || continue
    printf '%s\n' "$tier"
  done < <(gitlore_active_tiers "$mempath")
}

# Merge root's block for each tier $2 lists, one per line, three-way with the
# tier's carrier, into directory $3: $3/tiers lists the tiers merged and $3/<n>
# holds the n-th one's merged, prefixed bullets, for gitlore_compose_root_bullets.
#
# Base is the carrier at the gitlink memory records at $4 — `:` its index, the
# gitlink root last composed against, or `HEAD:` in a merge's continuation,
# where the index already holds the tier's HEAD — ours root's lines for the
# tier, theirs the carrier at the tier's HEAD, through
# gitlore_index_merge (index-merge.sh): a line only the tier changed is adopted,
# a line only root changed stands, and one both changed apart is a diff3 chunk
# under git's labels — HEAD, the base commit, the tier's HEAD — unless $5 is
# `tier-wins`, which takes the tier's line and records it in $3/notes. A tier on its pin
# merges to root's own lines, since base equals theirs. A tier root holds no
# line for is left out, for the mount case of gitlore_compose_root_bullets.
#
# Returns 0; 1 when a merge left a chunk; 2, with one problem per tier on
# stdout, when a base commit is not in the tier or a side cannot be merged
# entry-wise. A base the tier does not hold composes nothing: an empty base
# would read every line root dropped as one the tier added.
gitlore_compose_merge_tiers() {
  local mempath="$1" tiers="$2" dir="$3" at="$4" mode="${5-}" notes=""
  local root="$mempath/MEMORY.md" tier tierpath base head line path n=0 rc=0 mrc problems=""
  : > "$dir/tiers" || return 2
  if [ "$mode" = tier-wins ]; then
    notes="$dir/notes"
    : > "$notes" || return 2
  fi
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    [ -e "$tierpath/.git" ] || continue
    gitlore_index_has_tier "$root" "$tier" || continue
    head=$(git -C "$tierpath" rev-parse -q --verify HEAD) || continue
    # `-q --verify` is silent on the expected miss: a tier memory does not
    # record yet, whose base is empty.
    base=$(git -C "$mempath" rev-parse -q --verify "$at$tier") || base=""
    if [ -n "$base" ] && ! git -C "$tierpath" rev-parse -q --verify "${base}^{commit}" >/dev/null; then
      problems="${problems}$tierpath/MEMORY.md: the memory store records commit ${base:0:12} for tier '$tier', which the tier does not hold, so its lines cannot be merged into the root index
"
      continue
    fi
    : > "$dir/base" && : > "$dir/ours" || return 2
    if [ -n "$base" ]; then
      gitlore_carrier_bullets_at "$tierpath" "$base" "$tier" "$dir/raw" > "$dir/base" || return 2
    fi
    gitlore_carrier_bullets_at "$tierpath" "$head" "$tier" "$dir/raw" > "$dir/theirs" || return 2
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in "$tier"/*) printf '%s\n' "$line" >> "$dir/ours" ;; esac
    done < <(gitlore_index_part "$root" bullets)
    mrc=0
    gitlore_index_merge "$dir/base" "$dir/ours" "$dir/theirs" HEAD "$base" "$head" "$notes" "$tier" \
      > "$dir/merged" || mrc=$?
    if [ "$mrc" -ge 2 ]; then
      problems="${problems}$tierpath/MEMORY.md: tier '$tier''s index at ${head:0:12} cannot be merged entry-wise into the root index
"
      continue
    fi
    [ "$mrc" -eq 0 ] || rc=1
    n=$((n + 1))
    mv -- "$dir/merged" "$dir/$n" || return 2
    printf '%s\n' "$tier" >> "$dir/tiers" || return 2
  done <<EOF
$tiers
EOF
  if [ -n "$problems" ]; then
    printf '%s' "$problems"
    return 2
  fi
  return "$rc"
}

# Print the bullets of the carrier tier $1 holds at commit $2, prefixed with tier
# $3; a commit with no index prints nothing. $4 is a scratch file.
gitlore_carrier_bullets_at() {
  local tierpath="$1" commit="$2" tier="$3" raw="$4" line
  git -C "$tierpath" rev-parse -q --verify "$commit:MEMORY.md" >/dev/null || return 0
  git -C "$tierpath" show "$commit:MEMORY.md" > "$raw" || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    gitlore_bullet_reprefix "$line" "$tier" || continue
  done < <(gitlore_index_part "$raw" bullets)
}

# Print the number of the first line of file $2 that is exactly $1; return 1
# when none is.
gitlore_line_number() {
  local want="$1" file="$2" line n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if [ "$line" = "$want" ]; then printf '%s\n' "$n"; return 0; fi
  done < "$file"
  return 1
}
