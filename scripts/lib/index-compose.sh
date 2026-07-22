#!/usr/bin/env bash
# Tier index composition (D17 slice 3-ii). Splices each ACTIVE tier's carrier
# bullets into the root MEMORY.md (prefix-added) and mirrors root-authored tier
# bullets back down into every MOUNTED tier's carrier (prefix-stripped).
#
# Composition is PLACEMENT ONLY: it never edits a bullet's text, never touches
# project bullets, never creates or deletes a memory file. Line identity is the
# path prefix — no sentinel text is injected into any index.

# Print the path of a pointer bullet; return 1 if $1 is not one. A bullet is
# `- [` ... `](` PATH `)` ... — the hook (if any) is irrelevant here. Pure
# parameter expansion: no field splitting, so a path or title containing
# whitespace is safe.
gitlore_bullet_path() {
  local line="$1" rest path
  case "$line" in
    '- ['*) ;;
    *) return 1 ;;
  esac
  case "$line" in
    *']('*) ;;
    *) return 1 ;;
  esac
  rest=${line#*](}                 # "foo.md) — hook"
  case "$rest" in
    *')'*) ;;
    *) return 1 ;;
  esac
  path=${rest%%)*}
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

# Print $1 with "$2/" inserted before its path. Return 1 if $1 is not a bullet.
gitlore_bullet_reprefix() {
  local line="$1" prefix="$2" left rest path tail
  gitlore_bullet_path "$line" >/dev/null || return 1
  left=${line%%](*}                # "- [Title"
  rest=${line#*](}                 # "foo.md) — hook"
  path=${rest%%)*}
  tail=${rest#*)}                  # " — hook"
  printf '%s](%s/%s)%s\n' "$left" "$prefix" "$path" "$tail"
}

# Print $1 with a leading "$2/" removed from its path. Return 1 if $1 is not a
# bullet or its path does not carry that prefix.
gitlore_bullet_deprefix() {
  local line="$1" prefix="$2" left rest path tail
  path=$(gitlore_bullet_path "$line") || return 1
  case "$path" in
    "$prefix"/*) ;;
    *) return 1 ;;
  esac
  left=${line%%](*}
  rest=${line#*](}
  tail=${rest#*)}
  printf '%s](%s)%s\n' "$left" "${path#"$prefix"/}" "$tail"
}

# Print "FIRST LAST", the 1-indexed line numbers of the first and last pointer
# bullet in $1, or "0 0" when there are none. Space-separated so callers can
# `read` the pair instead of doing tab arithmetic in a parameter expansion.
gitlore_index_region() {
  local line first=0 last=0 n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if gitlore_bullet_path "$line" >/dev/null; then
      [ "$first" -eq 0 ] && first=$n
      last=$n
    fi
  done < "$1"
  printf '%s %s\n' "$first" "$last"
}

# Print one part of an index: "preamble" (before the first bullet), "bullets"
# (the region between the first and last bullet, inclusive), or "trailer"
# (after the last bullet). A bulletless index is ALL preamble — which is the
# day-one state of a freshly seeded tier carrier.
gitlore_index_part() {
  local file="$1" part="$2" first last
  read -r first last < <(gitlore_index_region "$file")
  if [ "$first" -eq 0 ]; then
    case "$part" in
      preamble) cat "$file" ;;
      *) : ;;
    esac
    return 0
  fi
  case "$part" in
    preamble) [ "$first" -gt 1 ] && sed -n "1,$((first - 1))p" "$file" ;;
    bullets)  sed -n "$first,${last}p" "$file" ;;
    trailer)  sed -n "$((last + 1)),\$p" "$file" ;;
  esac
  return 0
}

# Print the first path component of $1 when it names a tier listed in the
# newline-separated $2; return 1 otherwise (a bare path, or a prefix that
# matches no mounted tier).
gitlore_tier_of() {
  local path="$1" tiers="$2" head t
  case "$path" in
    */*) head=${path%%/*} ;;
    *) return 1 ;;
  esac
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    [ "$t" = "$head" ] && { printf '%s\n' "$head"; return 0; }
  done <<EOF
$tiers
EOF
  return 1
}

# Print one problem per line and return 1 when $1's store cannot be composed
# safely; print nothing and return 0 otherwise. Every problem is reported, not
# just the first: a user fixing a broken store wants the whole list.
#
# The four rules (D17 3-ii):
#   1. no duplicate pointer path within any single index;
#   2. every manifest entry names a MOUNTED tier;
#   3. every root bullet with a "/" names a mounted tier — an unattributable
#      prefix has no carrier to survive in, so dropping it would be data loss;
#   4. no non-blank non-bullet line inside an index's bullet region — the
#      layout rule would relocate it and lose its position.
gitlore_compose_check() {
  local mempath="$1" mounted active problems="" tier file
  mounted=$(gitlore_tier_paths "$mempath")
  active=$(gitlore_active_tiers "$mempath")

  # Rule 2 — a listed tier must be mounted.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    if ! printf '%s\n' "$mounted" | grep -qxF -- "$tier"; then
      problems="${problems}the tier manifest lists '$tier', which is not mounted in $mempath/.gitmodules
"
    fi
  done <<EOF
$active
EOF

  # Rules 1 and 4 — for the root index and every mounted tier carrier.
  file="$mempath/MEMORY.md"
  [ -f "$file" ] && problems="${problems}$(gitlore_compose_check_index "$file")"
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    problems="${problems}$(gitlore_compose_check_index "$mempath/$tier/MEMORY.md")"
  done <<EOF
$mounted
EOF

  # Rule 3 — root bullets only; a carrier's own bullets are bare by construction.
  if [ -f "$mempath/MEMORY.md" ]; then
    local line path
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in */*) ;; *) continue ;; esac
      if ! gitlore_tier_of "$path" "$mounted" >/dev/null; then
        problems="${problems}root index line '$path' has a prefix naming no mounted tier — it is a leftover from a removed tier and must be fixed by hand
"
      fi
    done < "$mempath/MEMORY.md"
  fi

  [ -z "$problems" ] && return 0
  printf '%s' "$problems" | grep -v '^$'
  return 1
}

# Rules 1 and 4 for a single index file. Prints problems; always returns 0 (the
# caller aggregates).
gitlore_compose_check_index() {
  local file="$1" first last n=0 line path seen=""
  read -r first last < <(gitlore_index_region "$file")
  [ "$first" -eq 0 ] && return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if path=$(gitlore_bullet_path "$line"); then
      if printf '%s\n' "$seen" | grep -qxF -- "$path"; then
        printf '%s: duplicate pointer path %s\n' "$file" "$path"
      fi
      seen="$seen
$path"
    elif [ "$n" -gt "$first" ] && [ "$n" -lt "$last" ] && [ -n "${line//[[:space:]]/}" ]; then
      printf '%s: interleaved non-bullet line %s inside the pointer block\n' "$file" "$n"
    fi
  done < "$file"
  return 0
}

# Print one report line per pointer bullet whose target file is absent; return 0
# either way. This is the fifth compose validation, and the only one that
# REPORTS instead of refusing: a dangling line does not make the composed output
# wrong, and refusing would block every later index write over a stale line the
# agent can fix in one edit.
#
# Under presence-authority (D17) the index says what memory CONTAINS, so the
# missing FILE is the anomaly, not the line — which is why nothing here touches
# either surface. Reporting is the whole job.
gitlore_compose_dangling() {
  local mempath="$1" mounted tier file line path reported=""

  file="$mempath/MEMORY.md"
  if [ -f "$file" ]; then
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      [ -e "$mempath/$path" ] && continue
      printf '%s: %s names no file in the memory store\n' "$file" "$path"
      reported="$reported
$path"
    done < "$file"
  fi

  # Carrier lines too: a DORMANT tier's bullets never reach the root, so a
  # root-only scan would leave them unchecked for as long as the tier sleeps.
  mounted=$(gitlore_tier_paths "$mempath")
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    file="$mempath/$tier/MEMORY.md"
    [ -f "$file" ] || continue
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      [ -e "$mempath/$tier/$path" ] && continue
      # An active tier's line lives in both indexes and resolves to one file;
      # report the root's copy only, since that is the surface the agent edits.
      printf '%s\n' "$reported" | grep -qxF -- "$tier/$path" && continue
      printf '%s: %s names no file in the tier\n' "$file" "$path"
    done < "$file"
  done <<EOF
$mounted
EOF
  return 0
}

# Print the merged bullet list for tier $2 under store $1, unprefixed and in
# carrier order with root-only lines appended. The ROOT's text wins on a path
# present in both: the root index is canonical for a line's text (D17).
gitlore_compose_tier_bullets() {
  local mempath="$1" tier="$2"
  local carrier="$mempath/$tier/MEMORY.md"
  local root="$mempath/MEMORY.md"
  local line path stripped rootline seen=""

  # Root bullets belonging to this tier, prefix stripped, keyed by path.
  local rootbullets=""
  if [ -f "$root" ]; then
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in "$tier"/*) ;; *) continue ;; esac
      stripped=$(gitlore_bullet_deprefix "$line" "$tier") || continue
      rootbullets="$rootbullets$stripped
"
    done < "$root"
  fi

  # Carrier order first; each line replaced by the root's version when present.
  if [ -f "$carrier" ]; then
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      rootline=$(printf '%s' "$rootbullets" | gitlore_compose_pick "$path")
      if [ -n "$rootline" ]; then printf '%s\n' "$rootline"; else printf '%s\n' "$line"; fi
      seen="$seen
$path"
    done < <(gitlore_index_part "$carrier" bullets)
  fi

  # Then root-only lines, in root order.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path=$(gitlore_bullet_path "$line") || continue
    printf '%s\n' "$seen" | grep -qxF -- "$path" && continue
    printf '%s\n' "$line"
  done <<EOF
$rootbullets
EOF
}

# Filter stdin (bullets) to the first one whose path is $1. Helper for the
# merge above; keeps the path comparison out of a subshell-heavy inline loop.
gitlore_compose_pick() {
  local want="$1" line path
  while IFS= read -r line; do
    path=$(gitlore_bullet_path "$line") || continue
    if [ "$path" = "$want" ]; then printf '%s\n' "$line"; return 0; fi
  done
  return 0
}

# Replace $1's bullet region with the bullets on stdin, preserving preamble and
# trailer. Writes only when the result differs, so an already-canonical index
# produces no churn; prints "composed <file>" when it did write.
gitlore_compose_write() {
  local file="$1" tmp="$1.gitlore-compose.tmp" bullets
  bullets=$(cat)
  {
    gitlore_index_part "$file" preamble
    [ -n "$bullets" ] && printf '%s\n' "$bullets"
    gitlore_index_part "$file" trailer
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  if cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    return 0
  fi
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  printf 'composed %s\n' "$file"
}

# The whole pass. Validates first; on any problem prints the problems, writes
# nothing, and returns 1 — fail-safe, so a broken store is never half-rewritten.
# Otherwise mirrors down into every MOUNTED tier (a dormant tier still receives
# its root lines: dropping them would be data loss, not dormancy — the same rule
# the commit/push lockstep applies) and splices up every ACTIVE tier.
gitlore_compose() {
  local mempath="$1"
  local root="$mempath/MEMORY.md"
  local mounted active tier line path changed=""
  [ -f "$root" ] || return 0

  if ! gitlore_compose_check "$mempath"; then
    return 1
  fi

  mounted=$(gitlore_tier_paths "$mempath")
  active=$(gitlore_active_tiers "$mempath")

  # Mirror down — every mounted tier with a checked-out carrier.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    changed="$changed$(gitlore_compose_tier_bullets "$mempath" "$tier" \
      | gitlore_compose_write "$mempath/$tier/MEMORY.md")
"
  done <<EOF
$mounted
EOF

  # Splice up — active tiers in manifest order, then the project's own bullets.
  changed="$changed$( {
    while IFS= read -r tier; do
      [ -n "$tier" ] || continue
      [ -f "$mempath/$tier/MEMORY.md" ] || continue
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        gitlore_bullet_reprefix "$line" "$tier"
      done < <(gitlore_index_part "$mempath/$tier/MEMORY.md" bullets)
    done <<INNER
$active
INNER
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in */*) continue ;; esac
      printf '%s\n' "$line"
    done < <(gitlore_index_part "$root" bullets)
  } | gitlore_compose_write "$root" )"

  [ -n "$changed" ] && printf '%s\n' "$changed"
  return 0
}
