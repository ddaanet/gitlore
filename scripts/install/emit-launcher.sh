#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT must be set}"

# Repo-local committed shim.
mkdir -p .gitlore/bin
cp "$PLUGIN_ROOT/scripts/install/launcher-shim" .gitlore/bin/claude
chmod 755 .gitlore/bin/claude

# direnv: prepend .gitlore/bin to PATH. Each PATH_add prepends, so the LAST one
# wins the front slot — our line must land after any pre-existing PATH_add.
line='PATH_add .gitlore/bin'
if [ ! -f .envrc ]; then
  printf '%s\n' "source_up_if_exists" "$line" > .envrc
elif ! grep -qxF "$line" .envrc; then
  last=$(grep -nE '^[[:space:]]*PATH_add( |$)' .envrc | tail -n1 | cut -d: -f1 || true)
  if [ -n "${last:-}" ]; then
    tmp=$(mktemp)
    awk -v n="$last" -v ins="$line" 'NR==n{print; print ins; next} {print}' .envrc > "$tmp"
    mv "$tmp" .envrc
  else
    printf '%s\n' "$line" >> .envrc
  fi
fi
