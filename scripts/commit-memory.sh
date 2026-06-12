#!/usr/bin/env bash
set -euo pipefail

# Standalone blessed entry point (D16): commit the memory submodule and advance
# local `live` without a parent commit. Arg-driven, git-commit-style:
#   commit-memory.sh -m "<summary>"     # inline
#   commit-memory.sh -F <file>          # read summary from a file
#   commit-memory.sh -F -               # read summary from stdin (heredoc)
# Activation is the gitlore-memory submodule registration (FR12), same gate as
# pre-commit. Discover this script via `git config gitlore.commitCommand`.

# Defensive: a caller's env may carry leaked repo-local GIT_* vars (see
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

summary=""
have_summary=0
while [ $# -gt 0 ]; do
  case "$1" in
    -m)
      summary="${2-}"; have_summary=1; shift 2 ;;
    -F)
      if [ "${2-}" = "-" ]; then summary="$(cat)"; else summary="$(cat "${2-}")"; fi
      have_summary=1; shift 2 ;;
    *)
      echo "usage: commit-memory.sh [-m <summary> | -F <file> | -F -]" >&2
      exit 2 ;;
  esac
done

mempath=$(gitlore_memory_path 2>/dev/null) || mempath=""

# Activation: no gitlore-memory submodule → nothing to do.
[ -z "$mempath" ] && exit 0
# Session-less worktree: memory worktree not materialized → nothing to do.
[ ! -e "$mempath/.git" ] && exit 0

# Arg-driven approval: when memory is dirty we need a summary to write into the
# commit-msg IPC file, which satisfies gitlore_sync_memory_to_live's freshness
# gate by construction (written immediately before the commit).
if [ "$(gitlore_memory_dirty "$mempath")" = "1" ]; then
  if [ "$have_summary" = "0" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: memory is dirty; commit-memory needs an approved summary. Pass it with -m <summary> or -F - (heredoc)." \
      "gitlore: memory has uncommitted changes; run this from Claude Code with an approved summary." >&2
    exit 1
  fi
  msgfile=$(gitlore_commit_msg_file "$mempath")
  printf '%s\n' "$summary" > "$msgfile"
fi

gitlore_sync_memory_to_live "$mempath"
exit $?
