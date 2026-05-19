#!/usr/bin/env bash
set -euo pipefail

mempath="${1:-memory}"
precommit_cmd="${2:-}"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

# Must be at repo root.
toplevel=$(git rev-parse --show-toplevel)
[ "$PWD" = "$toplevel" ] || { echo "Run /gitlore:install from the repo root ($toplevel)." >&2; exit 1; }

# Refuse non-empty existing path that isn't already our submodule.
if [ -e "$mempath" ] && ! git config --file .gitmodules "submodule.gitlore-memory.path" 2>/dev/null | grep -qx "$mempath"; then
  if [ -n "$(ls -A "$mempath" 2>/dev/null || true)" ]; then
    echo "gitlore: '$mempath' exists and is not empty. Choose another path." >&2
    exit 2
  fi
fi

bash "$PLUGIN_ROOT/scripts/install/init-submodule.sh" "$mempath"
bash "$PLUGIN_ROOT/scripts/install/write-settings.sh" "$mempath" "$precommit_cmd"
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

# Stage the tracked artifacts written by write-settings.sh and wire-*.sh so the
# install's contract (commands/gitlore/install.md) holds: everything we promise
# as "staged for review" actually is. .gitmodules and $mempath are staged by
# init-submodule.sh; settings.local.json is gitignored by design.
git add .claude/settings.json .claude/gitlore-hook-setup .gitignore

echo "gitlore: install complete." >&2
echo "Review the staged changes (.gitmodules, $mempath/, .claude/settings.json, .claude/gitlore-hook-setup, .gitignore) and commit when ready." >&2
