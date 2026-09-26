#!/usr/bin/env bash
set -euo pipefail

# Standalone blessed entry point (D16): commit the memory submodule and advance
# local `live` without a parent commit. Arg-driven, git-commit-style:
#   commit-memory.sh -m "<summary>"     # inline
#   commit-memory.sh -F <file>          # read summary from a file
#   commit-memory.sh -F -               # read summary from stdin (heredoc)
#   commit-memory.sh                    # bare: commit on the approval already
#                                       # on disk, judged by freshness
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

usage() { echo "usage: commit-memory.sh [-m <summary> | -F <file> | -F - | bare]" >&2; exit 2; }
summary=""
have_summary=0
while [ $# -gt 0 ]; do
  # Operand checked up front: `shift 2` past the end returns 1, which under
  # `set -e` would end the script with no message at all.
  case "$1" in
    -m)
      [ $# -ge 2 ] || usage
      summary="$2"; have_summary=1; shift 2 ;;
    -F)
      [ $# -ge 2 ] || usage
      if [ "$2" = "-" ]; then summary="$(cat)"; else summary="$(cat "$2")"; fi
      have_summary=1; shift 2 ;;
    *) usage ;;
  esac
done

mempath=$(gitlore_memory_path) || mempath=""

# Activation: no gitlore-memory submodule → nothing to do.
[ -z "$mempath" ] && exit 0
# Session-less worktree: memory worktree not materialized → nothing to do.
[ ! -e "$mempath/.git" ] && exit 0

# Arg-driven approval: when memory is dirty and a summary arrived with the
# call, write it into the commit-msg IPC file, which satisfies
# gitlore_sync_memory_to_live's freshness gate by construction (written
# immediately before the commit). Bare (no summary) leaves the file as it
# stands and lets that freshness gate judge the approval already on disk.
if [ "$(gitlore_memory_dirty "$mempath")" = "1" ]; then
  msgfile=$(gitlore_commit_msg_file "$mempath")
  if [ "$have_summary" = "1" ]; then
    mkdir -p "$(dirname "$msgfile")"   # .claude/ may not exist yet in a fresh tree
    printf '%s\n' "$summary" > "$msgfile"
  fi
  # A prepared merge outranks the screen below. A merge state makes memory dirty
  # by construction — its checkout moved the worktree — so a store mid-merge
  # arrives here with nothing approved and would be answered by a request to
  # summarize, putting in front of the user a merge both of whose sides they
  # already approved (D49) in place of the directive /gitlore:resolve acts on.
  # The sync runs this same guard first; a state this call passes is clean by the
  # time it runs, so the second one costs a rev-parse and a stat. It goes after
  # the `-m`/`-F` write so an approval passed with the call is kept for the retry.
  gitlore_guard_stale_merge_state "$mempath" || exit 1
  # Every mounted tier gets the same guard: gitlore_sync_tiers_to_live prepares a
  # head-vs-live merge inside the tier's own gitdir, not the root's, so a tier
  # mid-merge with nothing approved must hand over that guard's directive too,
  # rather than fall through to the no-approval screen below.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -e "$mempath/$tier/.git" ] || continue
    gitlore_guard_stale_merge_state "$mempath/$tier" || exit 1
  done < <(gitlore_tier_paths "$mempath")
  # Screened on both arms, after the write, because `-m ""` and `-F -` over empty
  # stdin both reach here; memory-commit-batch.sh screens with the same predicate.
  if ! gitlore_approval_present "$msgfile"; then
    gitlore_say_for_agent_or_user \
      "gitlore: memory is dirty; commit-memory needs an approved summary. Pass it with -m <summary> or -F - (heredoc)." \
      "gitlore: memory has uncommitted changes; run this from Claude Code with an approved summary." >&2
    exit 1
  fi
fi

gitlore_sync_memory_to_live "$mempath"
exit $?
