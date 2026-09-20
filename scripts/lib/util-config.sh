#!/usr/bin/env bash
# Tier discovery/listing (gitlore_tier_paths, gitlore_active_tiers,
# gitlore_active_tier_scopes) and store remote/publishing configuration
# (gitlore_memory_remote_name, gitlore_memory_approval_clause,
# gitlore_parent_visibility). Function-only — no readonly, no top-level
# state — so unlike util.sh it is safe to source twice; definition order
# relative to util.sh does not matter, since a call only needs the
# other file's functions defined by the time it runs, not by the time
# this one is sourced.
# Part of lib/util.sh; source that, not this file.

# Print each tier submodule's path (relative to the memory worktree), one per
# line, read from the memory store's OWN .gitmodules. Discovery is by enclosure:
# every submodule registered inside the memory store is a tier — there is no
# tier-name constant (D17). No output (exit 0) when there is no nested .gitmodules.
# Args: $1 = memory worktree path.
# Whitespace safety: `-z` emits one NUL-terminated "key\nvalue" record per match,
# so a submodule name or path containing spaces survives intact. (A field split on
# the plain output loses both: for `[submodule "a b"]` it yields `b.path`, part of
# the KEY.) Paths containing a newline are out of scope by construction — the
# activation manifest is line-oriented, so such a tier could never be listed.
# No stderr redirect: --get-regexp is silent on no-match (rc=1, verified), so any
# message here is a real failure worth seeing.
gitlore_tier_paths() {
  local mempath="$1" rec
  [ -f "$mempath/.gitmodules" ] || return 0
  # LC_ALL=C: matches gitlore_commit_msg_freshness's own NUL-delimited `read`,
  # against the bash 5.0-5.3 multibyte `read -d ''` overshoot (BP#65).
  while IFS= LC_ALL=C read -r -d '' rec; do
    printf '%s\n' "${rec#*$'\n'}"
  done < <(git config --file "$mempath/.gitmodules" -z --get-regexp '^submodule\..*\.path$')
  return 0
}

# Print the tier paths listed in the activation manifest <mempath>/.gitlore-tiers,
# in file order, one per line, whitespace-trimmed, skipping blank lines. The
# manifest is the deliberate activation + precedence surface (listed = active,
# order = precedence); a mounted but unlisted tier is dormant. No output (exit 0)
# when the manifest is absent. (D17)
# Args: $1 = memory worktree path.
gitlore_active_tiers() {
  local manifest="$1/.gitlore-tiers" line
  [ -f "$manifest" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"     # trim leading whitespace
    line="${line%"${line##*[![:space:]]}"}"     # trim trailing whitespace
    [ -n "$line" ] && printf '%s\n' "$line"
  done < "$manifest"
  return 0
}

# Print "<tierpath>/ — <description>" (or bare "<tierpath>/" when the tier has
# no MEMORY.md yet or no description) for every ACTIVE tier, in manifest order.
# A tier listed in the manifest but not actually mounted (`.git` missing) is
# skipped rather than reported, matching SessionStart's own guard — a stale
# manifest entry is a dangling-pointer concern, not this helper's job.
# Shared by SessionStart's routing-guidance banner and the post-mount triage
# nudge (D17 triage-automation design), so "active tiers and their scopes" has
# one definition. Depends on gitlore_get_frontmatter_description
# (scripts/lib/index-sync.sh) — callers must source that file too.
# Args: $1 = memory worktree path.
gitlore_active_tier_scopes() {
  local mempath="$1" tier tierpath desc
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    [ -e "$tierpath/.git" ] || continue
    desc=""
    if [ -f "$tierpath/MEMORY.md" ]; then
      desc=$(gitlore_get_frontmatter_description "$tierpath/MEMORY.md") || desc=""
    fi
    if [ -n "$desc" ]; then
      printf '%s/ — %s\n' "$tierpath" "$desc"
    else
      printf '%s/\n' "$tierpath"
    fi
  done < <(gitlore_active_tiers "$mempath")
  return 0
}

# Print the memory remote's bare name: <parent-remote-base>-memory.
# Derives the base from the parent repo's origin URL when set, handling both
# https (.../owner/repo[.git]) and scp-style (git@host:owner/repo[.git]) forms,
# with or without a trailing .git. Falls back to the repo directory basename when
# there is no origin (so the name is stable regardless of the local dir name when
# a remote exists — fixing the clone-dir-rename drift).
gitlore_memory_remote_name() {
  local url base
  url=$(git config --get remote.origin.url || true)
  if [ -n "$url" ]; then
    base=${url##*/}                       # https or scp-with-slash → repo[.git]
    case "$base" in *:*) base=${base##*:};; esac  # scp without a slash
    base=${base%.git}
  else
    base=$(basename "$(git rev-parse --show-toplevel)")
  fi
  printf '%s-memory\n' "$base"
}

# Print the canonical memory-approval clause: the self-contained block every
# call site that asks the user to approve a pending memory commit appends at the
# END of its own message. It carries a literal template, so it is multi-line and
# cannot be spliced into the middle of a sentence — a call site emitting JSON
# must therefore build it with jq, never a hand-written string. One file so the
# three call sites (post-tool-use.sh, memory-commit-batch.sh, resolve.sh) cannot
# drift on what "approve" means — see docs/design.md D19.
gitlore_memory_approval_clause() {
  cat "$PLUGIN_ROOT/reference/memory-approval-clause.txt"
}

# Print the visibility to use for the memory remote: "public" or "private".
# Matches the parent repo (design: public parent → public memory). Defaults to
# "private" when there is no parent origin or gh cannot report it — the safe
# default for memory, which may contain session context.
gitlore_parent_visibility() {
  local purl v
  purl=$(git config --get remote.origin.url || true)
  if [ -n "$purl" ] && command -v gh >/dev/null 2>&1; then
    # Redirect kept: this is a best-effort lookup whose failure modes are all
    # normal and expected (no gh auth, non-GitHub remote, network down, repo not
    # visible to this token) and each already has its answer — "private", the
    # safe default. Surfacing gh's error would put a scary, actionable-looking
    # message in front of a user for whom nothing is wrong.
    v=$(gh repo view "$purl" --json visibility -q .visibility 2>/dev/null \
          | tr '[:upper:]' '[:lower:]' || true)
    [ "$v" = "public" ] && { printf 'public\n'; return 0; }
  fi
  printf 'private\n'
}
