#!/usr/bin/env bash
set -euo pipefail

# Standalone push entry point (D20): publish the memory store and every mounted
# tier to their own remotes WITHOUT pushing the parent repo. The sibling of
# commit-memory.sh (D16) — that one satisfies the FR11 gate at an interactive
# moment, this one satisfies FR8 at one, so a session that commits memory and
# then ends can still leave every fact durable on its remote.
#
# Takes no arguments. There is nothing to approve: FR11 gated this content when
# it was committed, and publishing an already-approved commit adds no disclosure
# decision. Discover this script via `git config gitlore.pushCommand`.
#
# Guards exit 0 (FR12 coexistence, NFR8): not a gitlore repo, no gitlore-memory
# submodule, or a session-less worktree where memory was never checked out.
# Exit 1 carries a message on stderr naming the next action — including a
# prepared merge routed to /gitlore:resolve when a remote has diverged.

# Defensive: a caller's env may carry leaked repo-local GIT_* vars (see the
# pre-commit prologue). Clear the full local-env-var set, not a hand-picked
# subset — GIT_COMMON_DIR/GIT_OBJECT_DIRECTORY can redirect submodule git ops.
# shellcheck disable=SC2046  # intentional word-splitting of the var-name list
unset $(git rev-parse --local-env-vars)

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git config gitlore.hooksDir)/../..}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"

if [ $# -gt 0 ]; then
  echo "usage: push-memory.sh   (no arguments; FR11 approval happened at commit time)" >&2
  exit 2
fi

mempath=$(gitlore_memory_path) || mempath=""

# Activation: no gitlore-memory submodule → nothing to publish.
if [ -z "$mempath" ]; then
  printf 'gitlore: this repository has no gitlore-memory submodule; nothing to publish.\n'
  exit 0
fi
# Session-less worktree: memory worktree not materialized → nothing to publish.
if [ ! -e "$mempath/.git" ]; then
  # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
  printf 'gitlore: memory is not checked out in this worktree, so there is nothing to publish here. Run `git submodule update --init %s` first.\n' "$mempath"
  exit 0
fi

# Record where each store's remote sits BEFORE the push, so the report can say
# what actually moved rather than restating the refs. Tab-separated with the path
# LAST: a tier path may contain spaces, and only the final field can absorb them.
store_state() {
  local p="$1" sha
  sha=$(git -C "$p" rev-parse -q --verify refs/remotes/origin/live) || sha="-"
  printf '%s\t%s\n' "$sha" "$p"
}

store_paths=()
store_shas=()
while IFS=$'\t' read -r sha path; do
  [ -n "$path" ] || continue
  store_shas+=("$sha")
  store_paths+=("$path")
done < <(
  store_state "$mempath"
  # Same guard the push loop applies: `git -C` into an unchecked-out submodule
  # walks up to the enclosing repo, which would report MEMORY's ref as the tier's.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -e "$mempath/$tier/.git" ] || continue
    store_state "$mempath/$tier"
  done < <(gitlore_tier_paths "$mempath")
)

# The publish itself — shared verbatim with pre-push, so the tier-before-memory
# ordering and the divergence policy cannot drift between the two entry points.
gitlore_push_stores "$mempath"

# Reached only on success: gitlore_push_stores returns non-zero on every failure
# and `set -e` stops us above, so nothing below can report a push that did not
# happen. `origin/live` has been fetched and advanced by now, so old..new is what
# this run put on the remote.
published=0
i=0
while [ "$i" -lt "${#store_paths[@]}" ]; do
  p="${store_paths[$i]}"
  old="${store_shas[$i]}"
  i=$((i + 1))
  new=$(git -C "$p" rev-parse -q --verify refs/remotes/origin/live) || new="-"
  [ "$old" = "$new" ] && continue
  published=1
  if [ "$old" = "-" ]; then
    printf 'gitlore: %s — first publish, origin/live now %s\n' \
      "$p" "$(git -C "$p" rev-parse --short "$new")"
  else
    n=$(git -C "$p" rev-list --count "$old..$new") || n="?"
    printf 'gitlore: %s — published %s commit(s), origin/live now %s\n' \
      "$p" "$n" "$(git -C "$p" rev-parse --short "$new")"
  fi
done
[ "$published" = "1" ] || \
  printf 'gitlore: every store was already up to date; nothing needed publishing.\n'

# A push publishes commits, so uncommitted work is not a failure here — but it is
# the one thing a user who just asked to publish would be wrong to assume landed.
dirty=""
for p in "${store_paths[@]}"; do
  [ "$(gitlore_memory_dirty "$p")" = "1" ] && dirty="$dirty $p"
done
if [ -n "$dirty" ]; then
  printf 'gitlore: NOT published — uncommitted changes remain in:%s. Commit them (approved summary + memory commit) and push again.\n' "$dirty"
fi

exit 0
