#!/usr/bin/env bash
set -euo pipefail

# Standalone reconcile entry point: take what every store's remote is holding —
# each mounted tier first, then memory — and publish nothing. The sibling of
# push-memory.sh, which does both.
#
# It exists because a tier is PINNED at its gitlink (D17) and nothing advances it
# on its own any more. SessionStart names a tier whose remote is ahead; this is
# the command that acts on that, and the only one that does so without also
# putting local facts on a remote.
#
# Takes no arguments. There is nothing to approve: taking an already-published
# commit discloses nothing. Discover this script via `git config
# gitlore.mergeCommand`.
#
# Guards exit 0 (FR12 coexistence, NFR8): not a gitlore repo, no gitlore-memory
# submodule, or a session-less worktree where memory was never checked out.
# Exit 1 carries a message on stderr naming the next action — including a
# prepared merge routed to /gitlore:resolve when a store has diverged.

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
  echo "usage: merge-memory.sh   (no arguments)" >&2
  exit 2
fi

mempath=$(gitlore_memory_path) || mempath=""

if [ -z "$mempath" ]; then
  printf 'gitlore: this repository has no gitlore-memory submodule; there is nothing to reconcile.\n'
  exit 0
fi
if [ ! -e "$mempath/.git" ]; then
  # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
  printf 'gitlore: memory is not checked out in this worktree, so there is nothing to reconcile here. Run `git submodule update --init %s` first.\n' "$mempath"
  exit 0
fi

gitlore_merge_stores "$mempath"

# Reached only on success: gitlore_merge_stores returns non-zero on every failure
# and on a prepared merge, and `set -e` stops us above.
#
# A take commits its own bookkeeping (D49), so a dirty store here is the
# degraded path — the root held unapproved work, and the pair was staged
# instead. Say so rather than leaving the user to discover it.
if [ "$(gitlore_memory_dirty "$mempath")" = "1" ]; then
  printf 'gitlore: the memory store has uncommitted changes. Anything this take staged rides the next memory commit (approved summary), and reaches the remote on the next /gitlore:push.\n'
fi

exit 0
