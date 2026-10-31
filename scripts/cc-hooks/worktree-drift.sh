#!/usr/bin/env bash
# PostToolUse hook (matcher: EnterWorktree|ExitWorktree) — in-process worktree
# memory-drift guard (D15).
#
# Claude Code's in-process EnterWorktree moves the session cwd into a linked
# worktree but freezes the launch environment — including CLAUDE_PROJECT_DIR and
# the auto-memory directory. So memory written while in the worktree lands in the
# *launch* repo's submodule, not the worktree's. This hook fires once on the
# Enter/Exit transition (no per-tool cost, no de-dup needed) and, when the
# session has drifted into a linked worktree of the same gitlore repo, emits one
# user-visible systemMessage. ExitWorktree returns cwd to the launch root, so the
# drift predicate is false and the hook is silent — the asymmetry is intentional.
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")
case "$tool" in EnterWorktree|ExitWorktree) ;; *) exit 0 ;; esac

cwd=$(jq -r '.cwd // empty' <<<"$payload")
launch="${CLAUDE_PROJECT_DIR:-}"
# Without both the current cwd and the frozen launch root there is nothing to
# compare — bail rather than guess.
[ -n "$cwd" ] && [ -n "$launch" ] || exit 0

# Drift predicate: the current worktree's toplevel differs from the launch repo
# root, but both share one git common dir (a linked worktree of the *same* repo,
# not an unrelated directory). All git calls are read-only; any failure → bail.
# Redirects kept on this predicate block: it runs on every matching tool call and
# both paths may legitimately not be repos at all ("not a git repository" is the
# expected failure, and bailing out IS the handling). Anything that gets past it
# is reported normally below.
top_cwd=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
top_launch=$(CDPATH='' cd -- "$launch" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ "$top_cwd" != "$top_launch" ] || exit 0
# CDPATH='' cd --: --git-common-dir returns a relative '.git' in a main worktree,
# and a set CDPATH would resolve it against an unrelated directory *and* make cd
# echo the destination, corrupting the comparison below into a false match.
common_cwd=$(CDPATH='' cd -- "$cwd" && CDPATH='' cd -- "$(git rev-parse --git-common-dir)" && pwd) 2>/dev/null || exit 0
common_launch=$(CDPATH='' cd -- "$launch" && CDPATH='' cd -- "$(git rev-parse --git-common-dir)" && pwd) 2>/dev/null || exit 0
[ "$common_cwd" = "$common_launch" ] || exit 0

# Only meaningful for a gitlore-managed launch repo with memory enabled.
( cd "$launch" && gitlore_has_submodule ) || exit 0
[ -f "$launch/.claude/settings.json" ] || exit 0
# See session-start.sh: file-absent is guarded above, so a jq error here is a
# malformed settings.json and must not masquerade as "disabled".
enabled=$(jq -r '.gitlore.enabled // false' "$launch/.claude/settings.json" || echo false)
[ "$enabled" = "true" ] || exit 0
mempath=$(cd "$launch" && gitlore_memory_path)

jq -nc --arg wt "$top_cwd" --arg launch "$top_launch" --arg mem "$mempath" \
  '{systemMessage: ("gitlore: this session moved into a linked worktree (" + $wt + "), but Claude Code'"'"'s auto-memory stays pinned to the launch repo (" + $launch + "/" + $mem + "). Memory written here will land in the launch repo'"'"'s submodule, not this worktree'"'"'s. To redirect memory to this worktree, start Claude Code from inside it.")}'
