#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR"

# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"

# Guard 1: gitlore.enabled
enabled=$(jq -r '.gitlore.enabled // false' .claude/settings.json 2>/dev/null || echo false)
[ "$enabled" = "true" ] || exit 0

# Guard 2: gitlore-memory submodule registered
gitlore_has_submodule || exit 0

mempath=$(gitlore_memory_path)

# Keep stdout clean: everything below logs to stderr; only the guard JSON (if any)
# goes to real stdout (fd 3), which CC parses for systemMessage/additionalContext.
exec 3>&1 1>&2

# Standing commit-protocol orientation (Fix B / FR11). The base Claude Code memory
# instructions describe generic "edit files, save facts" memory with no review gate;
# in a gitlore repo that mental model is wrong and leads to direct submodule commits
# that bypass the gate. Emit the correct protocol every session, before the agent acts.
protocol_ctx="gitlore: memory in this repo lives in a git submodule guarded by a per-commit approval gate (FR11). NEVER commit inside the memory submodule directly — do not run 'git -C <mempath> commit' or 'cd <mempath> && git commit' (the submodule has a pre-commit hook that will block you). To persist memory: (1) summarize the pending memory changes in prose, (2) get explicit user approval, (3) write the approved summary to \$(git -C <mempath> rev-parse --git-path gitlore-commit-msg), (4) commit the PARENT repo — its pre-commit hook records, gates, and pushes memory for you."

# User-facing output (D14): every user-visible SessionStart notice rides the
# single SessionStart `systemMessage` (the only reliably user-visible hook
# channel; stderr is shown only on exit 2 / --verbose). `sysmsg` accumulates
# notices; `emit_session_json` writes the one JSON to fd 3 (systemMessage when
# non-empty, plus the standing commit-protocol additionalContext always).
sysmsg=""
add_sysmsg() {
  if [ -n "$sysmsg" ]; then sysmsg="$sysmsg

$1"; else sysmsg="$1"; fi
}
emit_session_json() {
  if [ -n "$sysmsg" ]; then
    jq -nc --arg sys "$sysmsg" --arg ctx "$protocol_ctx" \
      '{systemMessage:$sys, hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}' >&3
  else
    jq -nc --arg ctx "$protocol_ctx" \
      '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}' >&3
  fi
  exec 3>&- 1>&2
}

# Launcher guard (D10): without the shim, GITLORE_LAUNCHED is unset and CC's
# native auto-memory strands in ~/.claude/projects/<cwd>/memory instead of the submodule.
if [ -z "${GITLORE_LAUNCHED:-}" ]; then
  add_sysmsg "gitlore: memory is NOT redirected — this session was started with a plain 'claude', so auto-memory will strand in the default directory, not the submodule. Fix: run 'direnv allow' in this repo (or '/gitlore:install-launcher' if you don't use direnv), then restart Claude Code."
  protocol_ctx="$protocol_ctx

gitlore: GITLORE_LAUNCHED is unset — the launcher shim did not run, so CC auto-memory is writing to the default ~/.claude/projects/<cwd>/memory dir, NOT the gitlore submodule. Tell the user to run 'direnv allow' (Placement A) or '/gitlore:install-launcher' (Placement B) and restart. Do NOT write autoMemoryDirectory to any settings file — that tier is ignored (D10)."
fi

# Hook dir + wrappers.
git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
bash "$PLUGIN_ROOT/scripts/emit-wrappers.sh"

# Sentinel replay: re-apply hook-setup recorded at install time.
SENTINEL=".claude/gitlore-hook-setup"
if [ -f "$SENTINEL" ]; then
  cmd=$(head -1 "$SENTINEL" | tr -d '\n')
  case "$cmd" in
    "")
      echo "gitlore: empty sentinel; nothing to replay" >&2
      ;;
    direct)
      bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"
      ;;
    manual)
      echo "gitlore: hook wiring is 'manual'; verify your hooks still invoke \$(git rev-parse --git-common-dir)/gitlore-pre-*." >&2
      ;;
    *)
      sh -c "$cmd"
      ;;
  esac
fi

# Branch model: guard, submodule init, checkout, ff-merge.
parent_branch=$(gitlore_parent_branch)
if [ "$parent_branch" = "live" ]; then
  add_sysmsg "gitlore: parent branch 'live' collides with the memory trunk. Rename the parent branch (git branch -m) before continuing."
  emit_session_json
  exit 0
fi

# Memory working tree missing in this worktree. Two cases:
#  - submodule never initialized (main worktree, fresh clone) → submodule update;
#  - submodule initialized in the main repo but this is a *linked* worktree whose
#    memory tree was never checked out → create it from the shared submodule gitdir.
# Plain `git submodule update --init` does not reliably populate a submodule in a
# linked worktree, so the linked case uses an explicit `git worktree add`.
if [ ! -e "$mempath/.git" ]; then
  common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)
  mem_gitdir="$common_dir/modules/$GITLORE_SUBMODULE_NAME"
  if [ -d "$mem_gitdir" ]; then
    git -C "$mem_gitdir" worktree prune >/dev/null 2>&1 || true
    git -C "$mem_gitdir" worktree add --detach "$PWD/$mempath" live >&2
  else
    git submodule update --init -- "$mempath" >&2
  fi
fi

# Fresh clone (FR7): `git submodule update --init` checks out the recorded
# gitlink SHA as a detached HEAD and creates no local branches — only
# `origin/live` exists. The branch-model logic below references `live` as a
# *local* ref (checkout target and ff-merge source), so materialize it first.
# Prefer origin/live; fall back to the checked-out gitlink commit (HEAD) when
# the memory has no remote (degenerate, never-pushed case). No-op once live
# exists (install, normal sessions, linked worktrees).
if ! git -C "$mempath" show-ref --verify --quiet refs/heads/live; then
  if git -C "$mempath" show-ref --verify --quiet refs/remotes/origin/live; then
    gitlore_git -C "$mempath" branch live origin/live >&2
  else
    gitlore_git -C "$mempath" branch live HEAD >&2
  fi
fi

if [ "$parent_branch" = "DETACHED" ]; then
  gitlore_git -C "$mempath" checkout --detach live >/dev/null 2>&1 || true
else
  if git -C "$mempath" show-ref --verify --quiet "refs/heads/$parent_branch"; then
    gitlore_git -C "$mempath" checkout -q "$parent_branch"
  else
    gitlore_git -C "$mempath" checkout -q -b "$parent_branch" live
  fi
fi

# Wire the submodule-side commit gate (Fix A / FR11). Runs after the memory
# worktree exists so its gitdir hooks dir is resolvable. Idempotent; re-pins the
# submodule's gitlore.hooksDir to the live plugin each session.
bash "$PLUGIN_ROOT/scripts/emit-memory-gate.sh"

# Branch state for the success/divergence confirmation (D14).
if [ "$parent_branch" = "DETACHED" ]; then
  where="detached at live"
else
  where="branch '$parent_branch'"
fi

if [ "$(gitlore_memory_dirty "$mempath")" = "0" ]; then
  if gitlore_git -C "$mempath" merge --ff-only live >/dev/null 2>&1; then
    add_sysmsg "gitlore: memory ready ($where, synced with live)."
  else
    add_sysmsg "gitlore: memory $where diverged from live. Run /gitlore:resolve, then start a fresh session."
    emit_session_json
    exit 0
  fi
else
  add_sysmsg "gitlore: memory ready ($where); uncommitted changes present, skipped live sync."
fi

# Emit one SessionStart JSON: the commit-protocol additionalContext always, plus
# any accumulated user-facing systemMessage (success/dirty/launcher — D14).
emit_session_json
