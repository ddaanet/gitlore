#!/usr/bin/env bash
set -euo pipefail

# Standalone blessed entry point: write the composed tier indexes into the memory
# store. The commit path writes no index and aborts on one a compose pass would
# change; this is its remedy, and the pass a PostToolBatch hook makes for an edit
# made inside a session. Prints one `composed <file>` line per index written and
# nothing for a store that is already composed. Exits 1 when the pass refuses,
# with its problems on stderr, or leaves conflict markers in the root index,
# and 2 when a write failed partway.
# Callers run it as `gitlore-compose`, the plugin `bin/` name.

# shellcheck disable=SC2046  # intentional word-splitting of the var-name list
unset $(git rev-parse --local-env-vars)

PLUGIN_ROOT=$(CDPATH="" cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

# The launch repo, whatever directory the agent's shell is in; outside any
# worktree memory_path finds no .gitmodules and the run is a no-op.
launch_rc=0
gitlore_cd_launch_repo || launch_rc=$?
case "$launch_rc" in
  0 | 2) ;;
  1)
    echo "gitlore: nothing was composed: the project directory '$CLAUDE_PROJECT_DIR' cannot be entered." >&2
    exit 0 ;;
  *) exit 1 ;;
esac

mempath=$(gitlore_memory_path) || mempath=""
if [ -z "$mempath" ] || [ ! -e "$mempath/.git" ]; then
  echo "gitlore: nothing was composed: this repository has no materialized memory store." >&2
  exit 0
fi

rc=0
out=$(gitlore_compose "$mempath") || rc=$?
case "$rc" in
  0) [ -z "$out" ] || printf '%s\n' "$out" ;;
  1)
    printf 'gitlore: tier composition refused — the memory indexes were left untouched:\n%s\n' "$out" >&2
    exit 1
    ;;
  3)
    printf 'gitlore: the root index and a tier both changed the same lines, so the root index now holds conflict markers and no tier index was written:\n%s\nResolve each chunk to the line the root index should carry, then run gitlore-compose again.\n' "$out" >&2
    exit 1
    ;;
  *)
    printf 'gitlore: tier composition could not write an index — the memory indexes are only partly composed:\n%s\n' "$out" >&2
    exit 2
    ;;
esac
