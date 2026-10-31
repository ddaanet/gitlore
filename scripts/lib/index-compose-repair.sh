#!/usr/bin/env bash
# Compose-repair: the mechanical rewrite for compose-check's duplicate,
# weld and interleaved-line problems, restricted to weld targets that name a
# real file under the tier.
# Part of lib/index-compose.sh; source that, not this file.

# Rewrite <file> in place with the mechanical repair for rules 1, 4 and 6 above
# — welds, then interleaved non-bullet lines, then duplicate pointers, in that
# order — leaving every other line's bytes and relative order untouched. $2 is
# the pin's carrier, read as empty when it names no file; $3 is the tier
# directory a weld's second path must name a file under to count. Prints one
# report line per edit, nothing when none was made. Returns 0, or 1 when the
# rewrite could not be written, leaving the file unchanged.
gitlore_repair_index() {
  local file="$1" pin="$2" tierdir="$3"
  local line report="" i

  local pin_lines=""
  if [ -f "$pin" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      pin_lines="$pin_lines
$line"
    done < "$pin"
  fi

  # A redirected function call runs in this shell, so the screen costs no
  # subshell and only a line that carries a weld pays for the captures.
  local -a p1=()
  local cur second wpath
  while IFS= read -r line || [ -n "$line" ]; do
    cur="$line"
    while gitlore_weld_tail "$cur" >/dev/null &&
          wpath=$(gitlore_welded_path "$cur") && gitlore_repair_tier_file "$tierdir" "$wpath"; do
      second=$(gitlore_weld_tail "$cur")
      p1+=("${cur%"$second"}")
      report="${report}split a welded line before $wpath
"
      cur="$second"
    done
    p1+=("$cur")
  done < "$file"

  # Guarded before every expansion of an array that may be empty: bash before
  # 4.4 reads "${a[@]}" of an empty array as unbound under `set -u`. With no
  # bullet there is no weld, stray line or duplicate to repair.
  [ "${#p1[@]}" -gt 0 ] || return 0
  # gitlore_index_region's bounds, read off the split lines in this shell.
  local first=0 last=0 n=0
  for line in "${p1[@]}"; do
    n=$((n + 1))
    if gitlore_bullet_path "$line" >/dev/null; then
      [ "$first" -gt 0 ] || first=$n
      last=$n
    fi
  done
  [ "$first" -gt 0 ] || return 0
  n=0

  # The stray test is gitlore_compose_check_index's rule 4 test. Moved lines
  # land right after the last bullet, so the region's bounds stay put.
  # tagged follows the input's last line, or that line's tail after a weld
  # split — the one element termination can hinge on — by its index in p2;
  # p3tagged is its index in p3, or -1 when a drop retires it. That line is
  # never inside the region, so it is never moved.
  local -a p2=() stray=()
  local tagged=-1
  for line in "${p1[@]}"; do
    n=$((n + 1))
    if [ "$n" -gt "$first" ] && [ "$n" -lt "$last" ] &&
       [ -n "${line//[[:space:]]/}" ] && ! gitlore_bullet_path "$line" >/dev/null; then
      stray+=("$line")
      report="${report}moved a non-bullet line out of the pointer block: $line
"
      continue
    fi
    p2+=("$line")
    [ "$n" -lt "${#p1[@]}" ] || tagged=$((${#p2[@]} - 1))
    if [ "$n" -eq "$last" ] && [ "${#stray[@]}" -gt 0 ]; then
      p2+=("${stray[@]}")
    fi
  done

  # Duplicates, grouped by path. The first line the pin's carrier lacks
  # survives at its own position — the group's first line when it lacks them
  # all — and the first line survives when it lacks none. Only a bullet has a
  # path, and every bullet is inside the region, so no split is needed here.
  local m=${#p2[@]} j path survivor
  local -a paths=() grouped=() group=() drop=()
  i=0
  while [ "$i" -lt "$m" ]; do
    path=$(gitlore_bullet_path "${p2[i]}") || path=""
    paths[i]=$path
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$m" ]; do
    path=${paths[i]}
    if [ -n "$path" ] && [ -z "${grouped[i]:-}" ]; then
      group=()
      j=$i
      while [ "$j" -lt "$m" ]; do
        if [ "${paths[j]}" = "$path" ]; then
          group+=("$j")
          grouped[j]=1
        fi
        j=$((j + 1))
      done
      if [ "${#group[@]}" -gt 1 ]; then
        survivor=${group[0]}
        for j in "${group[@]}"; do
          # Here-string, not a pipe — see the note at gitlore_compose_check.
          if ! grep -qxF -- "${p2[j]}" <<<"$pin_lines"; then
            survivor=$j
            break
          fi
        done
        for j in "${group[@]}"; do
          [ "$j" = "$survivor" ] || drop[j]=1
        done
      fi
    fi
    i=$((i + 1))
  done
  local -a p3=()
  local p3tagged=-1
  i=0
  while [ "$i" -lt "$m" ]; do
    if [ -n "${drop[i]:-}" ]; then
      report="${report}dropped a duplicate pointer line: ${p2[i]}
"
    else
      p3+=("${p2[i]}")
      [ "$i" -ne "$tagged" ] || p3tagged=$((${#p3[@]} - 1))
    fi
    i=$((i + 1))
  done

  [ -n "$report" ] || return 0

  local dir scratch
  dir=$(dirname -- "$file")
  scratch=$(mktemp "$dir/.gitlore-repair-index.XXXXXX") || return 1
  # mktemp creates 0600; the copy carries <file>'s mode across the rename.
  cp -p -- "$file" "$scratch" || { rm -f "$scratch"; return 1; }

  local terminated=1
  [ -s "$file" ] && [ "$(tail -c 1 "$file" | wc -l | tr -d ' ')" = 0 ] && terminated=0

  # The output stays unterminated only when the input did and its own last
  # element is still the tagged one — the input's last line, or that line's
  # tail after a weld split. A drop or a move can retire that element or put
  # another after it; either way the element that ends up last is written with
  # a newline.
  local last_i=$((${#p3[@]} - 1))
  [ "$p3tagged" -eq "$last_i" ] || terminated=1

  if [ "$terminated" -eq 1 ]; then
    printf '%s\n' "${p3[@]}" > "$scratch" || { rm -f "$scratch"; return 1; }
  else
    i=0
    while [ "$i" -le "$last_i" ]; do
      if [ "$i" -eq "$last_i" ]; then
        printf '%s' "${p3[i]}"
      else
        printf '%s\n' "${p3[i]}"
      fi
      i=$((i + 1))
    done > "$scratch" || { rm -f "$scratch"; return 1; }
  fi

  mv -- "$scratch" "$file" || { rm -f "$scratch"; return 1; }
  printf '%s' "$report"
  return 0
}

# True when $2 names an existing file under tier directory $1. A `..`
# component or a leading `/` names no file of the tier's, whatever it reaches.
gitlore_repair_tier_file() {
  case "$2" in
    /*|..|../*|*/..|*/../*) return 1 ;;
  esac
  [ -f "$1/$2" ]
}
