#!/usr/bin/env bash
# Compose-project: the down projection into a tier's carrier, the root's
# composed bullet block, the up-adoption of a merged carrier, and the orphan
# report — the per-index projection work gitlore_compose drives.
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
# A tier is pinned at its gitlink, so the carrier cannot have moved on its own
# since the memory commit that recorded both surfaces — and when one has,
# gitlore_compose_check_pins refuses the whole pass, because root's older text
# would otherwise land on a carrier nothing had adopted up. What is left to
# decide is a carrier path root does not carry, and "root lacks it" alone is
# ambiguous — root may have deleted it, or may never have had it. Root at HEAD
# answers:
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
# A tier's lines are taken from ROOT, which is what keeps the in-session pass
# placement-only — it moves lines, it never rewrites one. Two cases read the
# carrier instead:
#
#   - $2 names the tier. An explicit adoption (gitlore_compose_up), run once when
#     a merge lands a carrier the user has approved: there the carrier is the
#     reviewed artifact and its text wins over whatever root still holds.
#   - root carries no line at all for an active tier. That is what a freshly
#     mounted or freshly activated tier looks like, and root has no opinion about
#     it yet, so it takes the carrier's — the augmentation a mount owes the
#     index. Deleting every one of a tier's lines from root therefore brings the
#     block back: the down projection skips a tier root has no line for, so the
#     carrier still holds them. Deactivating the tier is what drops its block.
#
# Lines prefixed with a mounted but DORMANT tier are dropped: root does not
# represent a dormant tier. They keep living in its carrier, and reactivating the
# tier brings them back through the case above.
gitlore_compose_root_bullets() {
  local mempath="$1" adopt="${2:-}"
  local root="$mempath/MEMORY.md" active tier line path
  active=$(gitlore_active_tiers "$mempath")

  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    if [ "$tier" = "$adopt" ] || ! gitlore_index_has_tier "$root" "$tier"; then
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

# Project tier $2's carrier UP into the root index and write it: root's block for
# that tier becomes the carrier's lines, prefixed, and every other line stays
# exactly where it is. This is the adoption step of a merge — the only moment a
# carrier is authoritative over root's text, because it is the artifact the user
# just approved.
#
# Writes no carrier, so a merge in one store never propagates into another the
# user did not review. Same three return codes as gitlore_compose.
gitlore_compose_up() {
  local mempath="$1" tier="$2"
  local root="$mempath/MEMORY.md"
  [ -f "$root" ] || return 0
  if ! gitlore_compose_check "$mempath"; then
    return 1
  fi
  local out
  if ! out=$(gitlore_compose_root_bullets "$mempath" "$tier" | gitlore_compose_write "$root"); then
    printf 'could not write %s\n' "$root"
    return 2
  fi
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

# Print one report line per ACTIVE tier carrier path that the composed root index
# does not carry; return 0 either way. Run AFTER a pass, like the dangling report
# and for the same reason: it describes the store as it now stands.
#
# A carrier line reaches the root unless root already had a block for that tier
# and never mentioned this path — a line written straight into the carrier, or
# one left there while the tier slept. Nothing is rewritten or dropped over it:
# it is a line whose two surfaces disagree about whether the fact is in play
# here, and which way to settle that is the agent's call, not the pass's. Either
# way is one edit, and the line names both: a carrier path that root at HEAD
# carries never survives a pass (the down projection reads it as root's
# deletion), so every orphan is one root never committed, and deleting it from
# the carrier is final.
gitlore_compose_orphans() {
  local mempath="$1" active tier line path
  active=$(gitlore_active_tiers "$mempath")
  [ -f "$mempath/MEMORY.md" ] || return 0
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      gitlore_index_has_path "$mempath/MEMORY.md" "$tier/$path" && continue
      # shellcheck disable=SC2016 # the backticks are report text, not a substitution
      printf '%s: %s is in the tier but not in the root index — delete its line from %s, or add `%s` to %s to recall it here\n' \
        "$mempath/$tier/MEMORY.md" "$path" "$mempath/$tier/MEMORY.md" \
        "$(gitlore_bullet_reprefix "$line" "$tier")" "$mempath/MEMORY.md"
    done < <(gitlore_index_part "$mempath/$tier/MEMORY.md" bullets)
  done <<EOF
$active
EOF
  return 0
}

# Return 0 when index $1 carries a pointer line for exactly path $2.
gitlore_index_has_path() {
  local file="$1" want="$2" line path
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    path=$(gitlore_bullet_path "$line") || continue
    [ "$path" = "$want" ] && return 0
  done < "$file"
  return 1
}

# Filter stdin (bullets) to the first one whose path is $1. Helper for the
# merge above; keeps the path comparison out of a subshell-heavy inline loop.
gitlore_compose_pick() {
  local want="$1" line path
  while IFS= read -r line || [ -n "$line" ]; do
    path=$(gitlore_bullet_path "$line") || continue
    if [ "$path" = "$want" ]; then printf '%s\n' "$line"; return 0; fi
  done
  return 0
}
