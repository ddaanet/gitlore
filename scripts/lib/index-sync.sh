#!/usr/bin/env bash
# One-way index→frontmatter sync helpers (D17). Sourced by the Pre/Post hooks
# and unit-tested directly. No side effects except the one write in the setter.

# Print "path<TAB>hook" for every root-index bullet of the form
#   - [title](path) — hook
# Lines lacking the ") — " separator are skipped. All width arithmetic uses
# length() so byte-vs-char counting stays self-consistent across awk flavors.
gitlore_index_pairs() {
  awk '
    /^- \[/ {
      sep = ") — "
      d = index($0, sep)
      if (d == 0) next
      left = substr($0, 1, d)              # "...(path)"
      hook = substr($0, d + length(sep))   # everything after the first ") — "
      lp = index(left, "](")
      if (lp == 0) next
      rest = substr(left, lp + 2)          # "path)"
      rp = index(rest, ")")
      if (rp == 0) next
      path = substr(rest, 1, rp - 1)
      print path "\t" hook                 # awk "\t" is a real tab, portably
    }
  ' "$1"
}

# Print the effective value of the first `description:` line in a file's
# leading frontmatter block; return 1 if there is none. A double-quoted scalar
# is unquoted, mirroring the setter's JSON quoting, so a value that round-trips
# through the setter compares equal to the hook it came from — otherwise every
# already-synced file would look like a fresh replacement.
gitlore_get_frontmatter_description() {
  local raw
  raw=$(awk '
    BEGIN { dashes = 0 }
    /^---[[:space:]]*$/ { dashes++; if (dashes == 2) exit; next }
    (dashes == 1 && /^description:/) {
      sub(/^description:[[:space:]]*/, ""); print; exit
    }
  ' "$1") || return 1
  [ -n "$raw" ] || return 1
  case "$raw" in
    # jq parses the setter's own output; a value that only looks quoted (stray
    # inner quotes, say) falls back to verbatim rather than vanishing.
    '"'*'"') jq -r . <<<"$raw" 2>/dev/null || printf '%s\n' "$raw" ;;
    *) printf '%s\n' "$raw" ;;
  esac
}

# Rewrite the first `description:` line inside a file's leading frontmatter
# block to a JSON-quoted (=> YAML-safe) scalar of $2. In place.
gitlore_set_frontmatter_description() {
  local file="$1" newdesc="$2" quoted repl tmp status
  quoted=$(jq -Rn --arg d "$newdesc" '$d')   # e.g. "has \"quote\": ..."
  repl="description: $quoted"
  tmp="$file.gitlore.tmp"
  # Pass repl via ENVIRON so awk does no escape processing on it. Both the
  # awk call and the mv are the condition of this `if`, so either one
  # failing (awk itself, the redirect that creates $tmp, or the mv) is
  # caught here instead of tripping errexit; on failure the (possibly
  # empty or partially-written) $tmp is removed so it never survives
  # inside the memory worktree — an untracked leftover there would make
  # gitlore_memory_dirty report dirty and get swept up by the FR11 memory
  # gate's `git add -A`. The original failing command's status is
  # preserved and returned so callers' `if !` guard still fires.
  if GITLORE_REPL="$repl" awk '
    BEGIN { dashes = 0; done = 0 }
    /^---[[:space:]]*$/ { dashes++; print; next }
    (dashes == 1 && !done && /^description:/) {
      print ENVIRON["GITLORE_REPL"]; done = 1; next
    }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"; then
    return 0
  else
    # $? after a bare `if cond; then ...; fi` with no branch taken is 0, not
    # the condition's status (POSIX) — capture it here, in the else branch,
    # while it is still live.
    status=$?
    rm -f "$tmp"
    return "$status"
  fi
}

# Abs/relative path of the pre-edit MEMORY.md stash, inside the submodule
# gitdir (untracked; mirrors gitlore_commit_msg_file). $1 = memory path.
gitlore_index_preimage_file() {
  git -C "$1" rev-parse --git-path gitlore-index-preimage
}
