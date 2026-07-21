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
