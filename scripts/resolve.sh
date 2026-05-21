#!/usr/bin/env bash
# Diagnose and repair gitlore remote state. Detection order matches
# Section 6.2 of the spec. Idempotent: a healthy state produces no changes.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"

# Subcommand dispatch (Plan 03 continuations).
if [ $# -ge 1 ]; then
  subcmd="$1"
  shift
  case "$subcmd" in
    continue-after-branch-merge)
      gitlore_has_submodule || { echo "gitlore: not installed" >&2; exit 1; }
      mempath=$(gitlore_memory_path)
      statefile=$(gitlore_merge_state_file "$mempath")
      [ -f "$statefile" ] || { echo "gitlore: no merge state file at $statefile" >&2; exit 1; }
      return_branch=$(jq -r .return_branch "$statefile")
      # Commit the merge (uses git's MERGE_MSG; live is HEAD = first parent per D6).
      git -C "$mempath" commit -q --no-edit
      # Advance the worktree branch to the merge commit and return.
      git -C "$mempath" branch -f "$return_branch" HEAD
      git -C "$mempath" checkout -q "$return_branch"
      rm -f "$statefile"
      # Retry the ff-push; on failure, loop with a fresh prepare.
      if ! git -C "$mempath" push -q . HEAD:live 2>/dev/null; then
        if ! prep_out=$(gitlore_prepare_branch_vs_live "$mempath"); then
          echo "gitlore: cannot checkout live (concurrent resolve). Wait and retry." >&2
          exit 1
        fi
        branch="${prep_out%%:*}"
        base="${prep_out#*:}"
        gitlore_write_merge_state "$mempath" "branch-vs-live" "$base" "$branch" "live" "$branch" "continue-after-branch-merge"
        gitlore_emit_merge_directive "$statefile" "branch-vs-live" "continue-after-branch-merge"
        exit 1
      fi
      exit 0
      ;;
    continue-after-remote-merge)
      gitlore_has_submodule || { echo "gitlore: not installed" >&2; exit 1; }
      mempath=$(gitlore_memory_path)
      statefile=$(gitlore_merge_state_file "$mempath")
      [ -f "$statefile" ] || { echo "gitlore: no merge state file at $statefile" >&2; exit 1; }
      return_branch=$(jq -r .return_branch "$statefile")
      # Commit the merge (origin/live is HEAD = first parent per D6).
      git -C "$mempath" commit -q --no-edit
      rm -f "$statefile"
      # Retry the push; on failure, loop with a fresh prepare.
      if ! git -C "$mempath" push -q origin live 2>/dev/null; then
        if ! prep_out=$(gitlore_prepare_local_vs_remote "$mempath"); then
          echo "gitlore: cannot checkout live (concurrent resolve). Wait and retry." >&2
          exit 1
        fi
        IFS=':' read -r return_branch base old_local <<< "$prep_out"
        gitlore_write_merge_state "$mempath" "local-vs-remote" "$base" "$old_local" "live" "$return_branch" "continue-after-remote-merge"
        gitlore_emit_merge_directive "$statefile" "local-vs-remote" "continue-after-remote-merge"
        exit 1
      fi
      git -C "$mempath" checkout -q "$return_branch"
      exit 0
      ;;
    *)
      # Other subcommands added in later tasks.
      echo "gitlore: unknown resolve subcommand: $subcmd" >&2
      exit 2
      ;;
  esac
fi

# Default mode: detect + try both pushes in turn. Yield on the first failure;
# continuations re-enter from the hook (commit/push retries), not from here.

gitlore_has_submodule || {
  gitlore_say_for_agent_or_user \
    "gitlore: not installed in this repo. Run /gitlore:install." \
    "gitlore: not installed in this repo. Open this project in Claude Code and run /gitlore:install." >&2
  exit 1
}
mempath=$(gitlore_memory_path)

# Existing Plan 02 simple repairs (remote.origin.url, ls-remote, push live)
# happen first — they precede semantic-merge detection.
remote_url=$(git -C "$mempath" config --get remote.origin.url 2>/dev/null || true)
if [ -z "$remote_url" ] || [ "$remote_url" = "./.git/gitlore-placeholder" ]; then
  echo "gitlore: no memory remote configured. Creating one." >&2
  bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" "$mempath"
  echo "gitlore: memory remote created and live pushed." >&2
  exit 0
fi
if ! git -C "$mempath" ls-remote origin >/dev/null 2>&1; then
  gitlore_say_for_agent_or_user \
    "gitlore: memory remote unreachable. Check network or 'gh auth status'." \
    "gitlore: memory remote unreachable. Check network or 'gh auth status'." >&2
  exit 1
fi
if ! git -C "$mempath" ls-remote origin live | grep -q .; then
  echo "gitlore: remote has no live branch. Pushing." >&2
  git -C "$mempath" push origin live
  exit 0
fi

git -C "$mempath" fetch -q origin live 2>/dev/null || true

# Try branch-vs-live first (cheaper, local-only).
branch=$(git -C "$mempath" symbolic-ref --short -q HEAD || echo "")
if [ -n "$branch" ] && [ "$branch" != "live" ]; then
  if ! git -C "$mempath" push -q . HEAD:live 2>/dev/null; then
    if ! prep_out=$(gitlore_prepare_branch_vs_live "$mempath"); then
      echo "gitlore: another session is resolving memory. Wait and retry." >&2
      exit 1
    fi
    branch_p="${prep_out%%:*}"; base_p="${prep_out#*:}"
    gitlore_write_merge_state "$mempath" "branch-vs-live" "$base_p" "$branch_p" "live" "$branch_p" "continue-after-branch-merge"
    gitlore_emit_merge_directive "$(gitlore_merge_state_file "$mempath")" "branch-vs-live" "continue-after-branch-merge"
    exit 1
  fi
fi

# Branch is in sync (or wasn't applicable). Try local-vs-remote.
if ! git -C "$mempath" push -q origin live 2>/dev/null; then
  if ! prep_out=$(gitlore_prepare_local_vs_remote "$mempath"); then
    echo "gitlore: another session is resolving memory. Wait and retry." >&2
    exit 1
  fi
  IFS=':' read -r return_branch base old_local <<< "$prep_out"
  gitlore_write_merge_state "$mempath" "local-vs-remote" "$base" "$old_local" "live" "$return_branch" "continue-after-remote-merge"
  gitlore_emit_merge_directive "$(gitlore_merge_state_file "$mempath")" "local-vs-remote" "continue-after-remote-merge"
  exit 1
fi

echo "gitlore: state is healthy. Nothing to do." >&2
exit 0
