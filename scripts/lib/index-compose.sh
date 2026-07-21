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
