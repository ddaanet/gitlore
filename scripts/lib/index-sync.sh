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

# Abs/relative path of the compose hook's own pre-batch stamp. A second,
# independently-owned file rather than a field in the sync's stash: each
# PostToolBatch hook consumes and deletes its own baseline, so neither depends
# on running before or after the other. $1 = memory path.
gitlore_compose_stamp_file() {
  git -C "$1" rev-parse --git-path gitlore-compose-stamp
}

# Print the compose trigger's stamp: one `key<TAB>checksum` line per watched
# file, with a literal `absent` for one that is not there — so a file appearing
# or vanishing registers as a change like any other. Cheap by design: it runs
# ahead of every Bash call, where keeping whole copies would not be.
# Args: $1 = root index path, $2 = tier manifest path.
gitlore_compose_stamp() {
  printf 'index\t%s\n' "$(_gitlore_file_stamp "$1")"
  printf 'manifest\t%s\n' "$(_gitlore_file_stamp "$2")"
}

_gitlore_file_stamp() {
  if [ -f "$1" ]; then cksum < "$1"; else printf 'absent'; fi
}

# Print the checksum a stamp records for key $1. Reads the stamp on stdin, so
# the same reader serves the file on disk and the one just computed.
gitlore_compose_stamp_get() {
  awk -F'\t' -v k="$1" '$1==k { sub(/^[^\t]*\t/, ""); print; exit }'
}

# --- routing-key advisories --------------------------------------------------
# The index one-liner is what CC's recall classifier matches against, and the
# sync above then overwrites the file's own `description:` with it — so a hook
# that carries no trigger degrades BOTH match surfaces at once, silently. The
# two checks below give that silence a voice. Neither can decide whether a hook
# is GOOD; each measures one thing that is countable.

# Advisory byte budget of the always-loaded index blob (25 KiB) and the fraction
# at which to speak up. Both overridable so a test drives the threshold instead
# of writing a 20KB fixture. This budget only reports; Claude Code's own loader
# is the hard cap, and it truncates lower — see
# memory/ddaanet/index-compaction-triggers.md.
: "${GITLORE_INDEX_BUDGET_BYTES:=25600}"
: "${GITLORE_INDEX_BUDGET_WARN_PCT:=80}"

# Percent of that budget the index occupies, floored. BYTES, not lines: the
# blob is loaded verbatim, so a handful of paragraph-length lines costs more
# than fifty terse ones.
gitlore_index_budget_pct() {
  local bytes
  bytes=$(wc -c < "$1") || return 1
  printf '%s\n' "$(( bytes * 100 / GITLORE_INDEX_BUDGET_BYTES ))"
}

# Once-per-episode markers. A nudge that fires on every batch is noise, so each
# advisory drops a marker keyed by session in the memory gitdir — hook-owned
# state the agent must never write — and checks for it before speaking.
# Args: $1 = memory worktree path; $2 = session id; $3 = marker kind.
_gitlore_nudge_file() {
  local safe
  safe=$(printf '%s' "${2:-nosession}" | LC_ALL=C sed 's/[^A-Za-z0-9-]/_/g')
  git -C "$1" rev-parse --git-path "gitlore-$3-nudged-$safe"
}

# Clear this session's marker of that kind, and sweep markers left by sessions
# that ended without one. Args as _gitlore_nudge_file.
_gitlore_nudge_reset() {
  local mempath="$1" kind="$3" marker dir
  marker=$(_gitlore_nudge_file "$mempath" "$2" "$kind")
  rm -f "$marker"
  dir=$(dirname -- "$marker")
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name "gitlore-$kind-nudged-*" -type f -mtime +7 -delete
  return 0
}

# Has the index byte-budget advisory already fired this episode?
# Args: $1 = memory worktree path; $2 = session id.
gitlore_index_budget_nudge_file() { _gitlore_nudge_file "$1" "$2" budget; }

# Re-arm the byte-budget advisory. Called at SessionStart and PreCompact, the
# two events that end the context a marker's "already told" claim rests on.
gitlore_index_budget_nudge_reset() { _gitlore_nudge_reset "$1" "$2" budget; }

# Has the mid-session plugin-upgrade notice already fired this episode (D21)?
# Args: $1 = memory worktree path; $2 = session id.
gitlore_upgrade_nudge_file() { _gitlore_nudge_file "$1" "$2" upgrade; }

# Re-arm the upgrade notice. A compaction re-arms it deliberately: what survives
# is a summary, and the session is still running the old plugin root.
gitlore_upgrade_nudge_reset() { _gitlore_nudge_reset "$1" "$2" upgrade; }

# "bytes<TAB>path" for the $2 (default 5) largest bullets, descending — where
# curation actually pays. LC_ALL=C so awk's length() counts bytes rather than
# characters; the separator alone is a 3-byte em-dash, so the two differ.
#
# The last stage reads to EOF instead of `head -n`: callers run with `set -o
# pipefail`, and an early-exiting consumer leaves `sort` writing into a closed
# pipe — SIGPIPE, exit 141, and the advisory lost on exactly the large indexes
# it exists to report on.
gitlore_index_largest() {
  local file="$1" n="${2:-5}"
  LC_ALL=C awk '
    /^- \[/ {
      sep = ") — "
      d = index($0, sep); if (d == 0) next
      left = substr($0, 1, d)
      lp = index(left, "]("); if (lp == 0) next
      rest = substr(left, lp + 2)
      rp = index(rest, ")"); if (rp == 0) next
      print length($0) "\t" substr(rest, 1, rp - 1)
    }
  ' "$file" | sort -rn | awk -v n="$n" 'NR <= n'
}

# Return 0 when $1 carries at least one LITERAL token — the kind of thing a
# future query actually contains: a backticked span, a flag, a path, a dotfile,
# a filename, $VAR, a key=value, a version, snake_case, camelCase, an acronym.
#
# Word-at-a-time rather than one big ERE because ERE word boundaries are not
# portable (GNU \b vs BSD [[:<:]]); splitting on whitespace makes the boundary
# safe by construction, so `well-known` is prose while `--flag` is a flag.
gitlore_index_has_literal() {
  awk '
    {
      n = split($0, w, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        t = w[i]
        gsub(/^[[("]+/, "", t); gsub(/[])".,;:?!]+$/, "", t)
        if (t == "") continue
        if (index(t, "`") > 0)   { hit = 1; break }   # `backticked span`
        if (index(t, "/") > 0)   { hit = 1; break }   # a/path or 2>/dev/null
        if (index(t, "=") > 0)   { hit = 1; break }   # key=value
        if (t ~ /^--?[A-Za-z]/)  { hit = 1; break }   # --flag, -C
        if (t ~ /^\.[A-Za-z]/)   { hit = 1; break }   # .gitmodules
        if (t ~ /^\$/)           { hit = 1; break }   # $VAR
        if (t ~ /^[0-9]+\.[0-9]/) { hit = 1; break }  # 2.47.3
        if (t ~ /\.(md|sh|json|py|bats|toml|ya?ml|lock|git|txt)$/) { hit = 1; break }
        if (t ~ /[A-Za-z0-9]_[A-Za-z0-9]/) { hit = 1; break }   # snake_case
        if (t ~ /[a-z][A-Z]/)    { hit = 1; break }   # camelCase
        if (t ~ /^[A-Z][A-Z0-9]+$/) { hit = 1; break }          # CC, FR11, API
      }
    }
    END { exit !hit }
  ' <<<"$1"
}

# Print the effective `type:` from a memory file's leading frontmatter — the
# indented `metadata:` form and the older top-level one both. Return 1 if
# absent. `node_type:` does not match: the pattern anchors `type:` to the start
# of the line modulo indentation.
gitlore_frontmatter_type() {
  local raw
  raw=$(awk '
    BEGIN { dashes = 0 }
    /^---[[:space:]]*$/ { dashes++; if (dashes == 2) exit; next }
    (dashes == 1 && /^[[:space:]]*type:[[:space:]]/) {
      sub(/^[[:space:]]*type:[[:space:]]*/, ""); print; exit
    }
  ' "$1") || return 1
  [ -n "$raw" ] || return 1
  printf '%s\n' "$raw"
}
