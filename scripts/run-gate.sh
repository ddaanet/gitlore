#!/usr/bin/env bash
# Run a quality gate, skipping it when the tree is byte-for-byte what it was
# the last time that gate passed.
#
# Usage: run-gate.sh NAME CMD [ARG...]
#
# This exists so `just prerelease` right after a green `just precommit` re-runs
# only the part precommit did not cover (the evals). Each gate keeps its own
# sentinel, so they invalidate together but skip independently.
#
# Set GITLORE_GATE_FORCE=1 to run regardless of the sentinel.
set -euo pipefail

[ "$#" -ge 2 ] || { printf 'usage: run-gate.sh NAME CMD [ARG...]\n' >&2; exit 2; }
name="$1"
shift

toplevel=$(git rev-parse --show-toplevel)
# `cd --` with CDPATH cleared: git hands back paths that may be relative, and a
# set CDPATH would silently resolve one against an unrelated directory.
unset CDPATH
cd -- "$toplevel"

# The whole tree, content-addressed. Built in a throwaway index so the real one
# is untouched: seed it from the real index (preserving staged additions and
# deletions), then `add -A` folds in every unstaged change including untracked
# non-ignored files. `write-tree` then yields an id that depends only on
# CONTENT — committing between two gate runs does not change it, which is the
# whole point, since a release commits after precommit goes green.
tree_hash() {
  local tmp_index real_index
  # Checked, not assumed: the caller runs this inside `$(...) || ...`, which
  # switches errexit off for everything within, so a failing mktemp would
  # otherwise fall through to `GIT_INDEX_FILE= git add -A`. That happens to
  # fail hard rather than hitting the real index (verified git 2.47.3), but
  # relying on it would leave the whole worktree one git version away from
  # being staged by a hashing routine.
  tmp_index=$(mktemp "${TMPDIR:-/tmp}/gitlore-gate-index.XXXXXX") || return 1
  real_index=$(git rev-parse --git-path index) || { rm -f -- "$tmp_index"; return 1; }
  if [ -f "$real_index" ]; then
    cp -- "$real_index" "$tmp_index"
  else
    rm -f -- "$tmp_index"
  fi
  # `add -A` can refuse outright — observed on a path type git will not index,
  # which a sandbox surfacing phantom home dotfiles produces on a real
  # checkout. Either step failing must yield NO hash rather than a partial one:
  # a hash built from a half-updated index can match a stale sentinel on the
  # NEXT run and skip a gate that should have run. No hash means the gate runs,
  # which is the safe direction. git's own message is left to stand.
  local rc=0
  GIT_INDEX_FILE="$tmp_index" git add -A || rc=$?
  if [ "$rc" -eq 0 ]; then
    GIT_INDEX_FILE="$tmp_index" git write-tree || rc=$?
  fi
  rm -f -- "$tmp_index"
  return "$rc"
}

sentinel_dir=$(git rev-parse --git-path gitlore/gates)
sentinel="$sentinel_dir/$name"

# Empty on failure: no hash means no skip and no record, so the gate runs.
current=$(tree_hash) || {
  current=""
  printf 'gate %s: could not hash the tree (see above) — running the gate.\n' \
    "$name" >&2
}

if [ -z "${GITLORE_GATE_FORCE:-}" ] && [ -n "$current" ] && [ -f "$sentinel" ] \
   && [ "$(cat -- "$sentinel")" = "$current" ]; then
  printf 'gate %s: tree unchanged since it last passed — skipping.\n' "$name"
  exit 0
fi

# Record only on success, and only the hash of the tree that actually passed.
"$@"

if [ -n "$current" ]; then
  mkdir -p -- "$sentinel_dir"
  printf '%s\n' "$current" > "$sentinel"
fi
