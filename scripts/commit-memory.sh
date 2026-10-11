#!/usr/bin/env bash
set -euo pipefail

# Standalone blessed entry point (D16): commit the memory submodule and advance
# local `live` without a parent commit. Arg-driven, git-commit-style:
#   commit-memory.sh -m "<summary>"     # inline
#   commit-memory.sh -F <file>          # read summary from a file
#   commit-memory.sh -F -               # read summary from stdin (heredoc)
#   commit-memory.sh                    # bare: commit on the approval already
#                                       # on disk, judged by freshness
# Activation is the gitlore-memory submodule registration (FR12). Discover this
# script via `git config gitlore.commitCommand`.

# Defensive: a caller's env may carry leaked repo-local GIT_* vars (see
# `.claude/rules/shell.md` "Git hook env leak"). Clear the full local-env-var set, not a hand-picked
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
  # Screened on both arms, after the write, because `-m ""` and `-F -` over empty
  # stdin both reach here; memory-commit-batch.sh screens with the same predicate.
  if ! gitlore_approval_present "$msgfile"; then
    # Every mounted tier gets the same guard before that refusal speaks:
    # gitlore_sync_tiers_to_live prepares a head-vs-live merge inside the tier's
    # own gitdir, not the root's, so a tier mid-merge with nothing approved hands
    # over that guard's directive instead of a request for a summary.
    # Inside this arm rather than ahead of it, the placement resolve-sync-memory.sh
    # gives its own refusal-side loop, and for the same reason: the guard's
    # stale-no-merge-head arm REPAIRS, writing into the tier, so running it over a
    # summary just passed with `-m` would make that approval stale by mtime and
    # refuse it one step later. The approved path keeps the sync's own per-tier
    # guard, which runs after the freshness read this one would invalidate.
    while IFS= read -r tier; do
      [ -n "$tier" ] || continue
      [ -e "$mempath/$tier/.git" ] || continue
      gitlore_guard_stale_merge_state "$mempath/$tier" || exit 1
    done < <(gitlore_tier_paths "$mempath")
    gitlore_say_for_agent_or_user \
      "gitlore: memory is dirty; commit-memory needs an approved summary. Pass it with -m <summary> or -F - (heredoc)." \
      "gitlore: memory has uncommitted changes; run this from Claude Code with an approved summary." >&2
    exit 1
  fi
fi

# Stage the memory gitlink into the superproject index (D58) when this run moved
# memory HEAD. A no-op run stages nothing. The staging is skipped during a replay
# (rebase, cherry-pick, revert): a replayed commit must keep the pointer it
# recorded, and the memory worktree does not move when the parent's HEAD does.
stage_memory_pointer() {
  local mempath="$1" super top rel p name op err
  super=$(git -C "$mempath" rev-parse --show-superproject-working-tree)
  [ -n "$super" ] || return 0
  top=$(git -C "$mempath" rev-parse --show-toplevel)
  rel="${top#"$super"/}"
  # Marker list: path:operation. A merge is deliberately absent — it is authored now.
  for marker in rebase-merge:rebase rebase-apply:rebase \
                CHERRY_PICK_HEAD:cherry-pick REVERT_HEAD:revert; do
    name="${marker%%:*}"
    p=$(git -C "$super" rev-parse --git-path "$name")
    case "$p" in /*) ;; *) p="$super/$p" ;; esac
    if [ -e "$p" ]; then
      op="${marker##*:}"
      echo "gitlore: $op in progress — skipping the staging of the memory pointer; stage it yourself once the $op is done." >&2
      return 0
    fi
  done
  if ! err=$(git -C "$super" add -- "$rel" 2>&1); then
    echo "gitlore: memory was committed, but its pointer could not be staged in the parent (git: $err). The pointer floats until you stage it." >&2
  fi
}

memory_before=$(git -C "$mempath" rev-parse HEAD)
gitlore_sync_memory_to_live "$mempath"
memory_after=$(git -C "$mempath" rev-parse HEAD)
if [ "$memory_before" != "$memory_after" ]; then
  stage_memory_pointer "$mempath"
fi
exit 0
