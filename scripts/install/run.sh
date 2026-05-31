#!/usr/bin/env bash
set -euo pipefail

mempath="${1:-memory}"
precommit_cmd="${2:-}"

# Self-locate so we work under the Claude Code Bash tool, where
# CLAUDE_PLUGIN_ROOT is injected for hooks but NOT for Bash commands.
# Export it so the child install scripts inherit a correct value.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

# Must be at repo root.
toplevel=$(git rev-parse --show-toplevel)
[ "$PWD" = "$toplevel" ] || { echo "Run /gitlore:install from the repo root ($toplevel)." >&2; exit 1; }

# Must be the main worktree. In a linked worktree the memory submodule is
# usually unchecked-out, and every `git -C memory` op below would silently walk
# up to the parent repo — staging the parent's HEAD as the memory gitlink and
# creating branches in the parent. A linked worktree's per-worktree git dir
# differs from the common git dir; the main worktree's matches.
git_dir=$(cd "$(git rev-parse --git-dir)" && pwd)
common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)
if [ "$git_dir" != "$common_dir" ]; then
  echo "gitlore: run /gitlore:install from the main worktree, not a linked worktree ($PWD)." >&2
  echo "gitlore: the main worktree is at $(dirname "$common_dir")." >&2
  exit 1
fi

bash "$PLUGIN_ROOT/scripts/install/preflight.sh"

# Refuse non-empty existing path that isn't already our submodule.
if [ -e "$mempath" ] && ! git config --file .gitmodules "submodule.gitlore-memory.path" 2>/dev/null | grep -qx "$mempath"; then
  # Partial prior install: module store absorbed + gitfile in place, but .gitmodules not yet written.
  # init-submodule.sh repairs .gitmodules; fall through rather than refusing.
  _common_dir=$(git rev-parse --git-common-dir)
  if [ -d "$_common_dir/modules/gitlore-memory" ] && [ -f "$mempath/.git" ]; then
    echo "gitlore: partial prior install detected at '$mempath' — resuming." >&2
  elif [ -n "$(ls -A "$mempath" 2>/dev/null || true)" ]; then
    echo "gitlore: '$mempath' exists and is not empty. Choose another path." >&2
    exit 2
  fi
fi

bash "$PLUGIN_ROOT/scripts/install/init-submodule.sh" "$mempath"
bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" "$mempath"
bash "$PLUGIN_ROOT/scripts/install/write-settings.sh" "$mempath" "$precommit_cmd"
bash "$PLUGIN_ROOT/scripts/install/emit-launcher.sh"
bash "$PLUGIN_ROOT/scripts/emit-wrappers.sh"

manager=$(bash "$PLUGIN_ROOT/scripts/hook-manager/detect.sh")
case "$manager" in
  lefthook)   bash "$PLUGIN_ROOT/scripts/hook-manager/wire-lefthook.sh"   ;;
  husky)      bash "$PLUGIN_ROOT/scripts/hook-manager/wire-husky.sh"      ;;
  overcommit) bash "$PLUGIN_ROOT/scripts/hook-manager/wire-overcommit.sh" ;;
  direct)     bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"     ;;
  manual)         bash "$PLUGIN_ROOT/scripts/hook-manager/wire-manual.sh" ;;
  multi:*)        bash "$PLUGIN_ROOT/scripts/hook-manager/wire-manual.sh" "${manager#multi:}" ;;
esac

# Catch-all for a stale Claude Code project-scoped auto-memory dir that
# init-submodule.sh did NOT migrate (re-run, or a pre-registered submodule where
# seeding was skipped). First-install migration is handled in init-submodule.sh,
# which already leaves the stub. Only act on an existing dir — never create one
# under the user's real ~/.claude when there was nothing to migrate.
_old_memory=$(gitlore_cc_memory_dir "$toplevel")
if [ -d "$_old_memory" ]; then
  # shellcheck disable=SC2016  # literal marker string, no expansion intended
  if ! grep -q 'migrated in-tree by `/gitlore:install`' "$_old_memory/MEMORY.md" 2>/dev/null; then
    echo "gitlore: migrated stale auto-memory at $_old_memory" >&2
  fi
  gitlore_mark_migrated "$_old_memory"
fi

# Stage the tracked artifacts written by write-settings.sh and wire-*.sh so the
# install's contract (commands/install.md) holds: everything we promise
# as "staged for review" actually is. .gitmodules and $mempath are staged by
# init-submodule.sh; settings.local.json is gitignored by design.
git add .claude/settings.json .claude/gitlore-hook-setup .gitignore .gitlore/bin/claude .envrc

if command -v direnv >/dev/null 2>&1; then
  direnv allow || true
else
  bash "$PLUGIN_ROOT/scripts/install/global-shim.sh"
fi

echo "gitlore: install complete." >&2
echo "Review the staged changes (.gitmodules, $mempath/, .claude/settings.json, .claude/gitlore-hook-setup, .gitignore, .gitlore/bin/claude, .envrc) and commit when ready." >&2
