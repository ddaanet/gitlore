#!/usr/bin/env bash
# wire-manual.sh — write a manual-wiring sentinel; print instructions to stderr.
# Arg 1 (optional): comma-separated list of detected managers, when multiple were found.
set -euo pipefail

detected="${1:-}"

mkdir -p .claude
printf 'manual\n' > .claude/gitlore-hook-setup

if [ -n "$detected" ]; then
  echo "gitlore: multiple hook managers detected ($detected); cannot pick safely." >&2
  echo "Disable all but one, or wire manually:" >&2
else
  echo "gitlore: no supported hook manager detected." >&2
  echo "Wire the wrappers into your hook system manually:" >&2
fi

cat >&2 <<'EOF'

  pre-commit → exec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"
  pre-push   → exec "$(git rev-parse --git-common-dir)/gitlore-pre-push" "$@"

(Resolve the wrapper through the git common dir so it works in linked worktrees.)
Once wired, run /gitlore:install again to re-detect.
EOF
