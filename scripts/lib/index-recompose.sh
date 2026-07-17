#!/usr/bin/env bash
# Structural recompose of the root MEMORY.md index (D17 slice 3a). Owns each
# bullet line's PRESENCE and PLACEMENT, never its TEXT. Sourced by SessionStart
# and unit-tested directly. Operations on the flat store: dedup by path, prune
# orphaned lines, seed coverage for uncovered files. Idempotent; writes only when
# the canonical form differs. Depends on gitlore_index_pairs and
# gitlore_get_frontmatter_description from index-sync.sh being sourced.

# Print the raw value of the first `<field>:` line in a file's leading
# frontmatter block (nothing if absent). $1 = file, $2 = field name. Unlike the
# description getter this does not unquote — callers that need unquoting use
# gitlore_get_frontmatter_description instead.
gitlore_frontmatter_field() {
  awk -v field="$2" '
    BEGIN { dashes = 0 }
    /^---[[:space:]]*$/ { dashes++; if (dashes == 2) exit; next }
    (dashes == 1) {
      if ($0 ~ "^" field ":") { sub("^" field ":[[:space:]]*", ""); print; exit }
    }
  ' "$1"
}

# Append a seed bullet line for every present file lacking a covered bullet.
# title = frontmatter `name` (fallback: basename sans .md); hook = frontmatter
# `description` (fallback: title, so a description-less file still carries real
# words for retrieval). Args: $1 mempath, $2 present-file, $3 covered-file,
# $4 seeds-file (appended). The agent owns the text thereafter (D17).
gitlore_build_coverage_seeds() {
  local mempath="$1" present="$2" covered="$3" seeds="$4"
  local p title desc hook
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    grep -qxF "$p" "$covered" && continue    # already has a bullet
    title=$(gitlore_frontmatter_field "$mempath/$p" name)
    [ -n "$title" ] || title="${p%.md}"
    desc=$(gitlore_get_frontmatter_description "$mempath/$p" 2>/dev/null) || desc=""
    if [ -n "$desc" ]; then hook="$desc"; else hook="$title"; fi
    printf -- '- [%s](%s) — %s\n' "$title" "$p" "$hook" >> "$seeds"
  done < "$present"
}

# Rewrite $1/MEMORY.md into its canonical structural form (dedup + prune +
# coverage). Prints 1 if it wrote, 0 if it did not. Returns 0 on success, 2 on
# a rewrite error (index left untouched). Never alters the text of a kept line.
gitlore_recompose_index() {
  local mempath="$1"
  local index="$mempath/MEMORY.md"
  [ -e "$index" ] || { printf '0\n'; return 0; }

  local present covered seeds tmp
  present=$(mktemp) || { printf '0\n'; return 2; }
  covered=$(mktemp) || { rm -f "$present"; printf '0\n'; return 2; }
  seeds=$(mktemp)   || { rm -f "$present" "$covered"; printf '0\n'; return 2; }
  # Rewrite temp lives beside the index (same filesystem → atomic mv) and is
  # removed on every exit path so it never survives inside the memory worktree.
  tmp="$index.gitlore-recompose.tmp"

  # Present memory files (flat store): top-level *.md except the index itself.
  local f base
  for f in "$mempath"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    [ "$base" = "MEMORY.md" ] && continue
    printf '%s\n' "$base" >> "$present"
  done

  # An empty present set would make awk prune every bullet — refuse to run
  # (protects against a mis-resolved mempath wiping the index).
  if [ ! -s "$present" ]; then
    rm -f "$present" "$covered" "$seeds"
    printf '0\n'; return 0
  fi

  # Paths already carrying a bullet.
  gitlore_index_pairs "$index" | cut -f1 > "$covered"

  gitlore_build_coverage_seeds "$mempath" "$present" "$covered" "$seeds"

  if ! awk -v PRESENT="$present" -v SEEDS="$seeds" '
    BEGIN {
      while ((getline p < PRESENT) > 0) if (p != "") present[p] = 1
      ns = 0
      while ((getline s < SEEDS) > 0) seed[ns++] = s
      havebullet = 0
    }
    {
      line = $0
      isbullet = 0
      if (line ~ /^- \[/) {
        isbullet = 1
        sep = ") — "; d = index(line, sep); path = ""
        if (d > 0) {
          left = substr(line, 1, d); lp = index(left, "](")
          if (lp > 0) {
            rest = substr(left, lp + 2); rp = index(rest, ")")
            if (rp > 0) path = substr(rest, 1, rp - 1)
          }
        }
        if (path != "") {
          if (!(path in present)) next     # prune orphan
          if (path in emitted) next         # dedup by path (keep first)
          emitted[path] = 1
        }
        # malformed bullet (no parseable path) falls through, kept verbatim
      }
      buf[nb++] = line
      if (isbullet) { havebullet = 1; lastbullet = nb - 1 }
    }
    END {
      for (i = 0; i < nb; i++) {
        print buf[i]
        if (havebullet && i == lastbullet)
          for (j = 0; j < ns; j++) print seed[j]
      }
      if (!havebullet)
        for (j = 0; j < ns; j++) print seed[j]
    }
  ' "$index" > "$tmp"; then
    rm -f "$tmp" "$present" "$covered" "$seeds"
    printf '0\n'; return 2
  fi

  local changed=0
  if ! cmp -s "$tmp" "$index"; then
    mv "$tmp" "$index"
    changed=1
  else
    rm -f "$tmp"
  fi
  rm -f "$present" "$covered" "$seeds"
  printf '%s\n' "$changed"
  return 0
}
