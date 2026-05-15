#!/usr/bin/env bash
# wire-manual.sh — write a manual-wiring sentinel; print instructions to stderr.
set -euo pipefail

mkdir -p .claude
printf 'manual\n' > .claude/gitlore-hook-setup

cat >&2 <<'EOF'
gitlore: no supported hook manager detected.
Wire the wrappers into your hook system manually:

  pre-commit → .git/gitlore-pre-commit
  pre-push   → .git/gitlore-pre-push

Once wired, run /gitlore:install again to re-detect.
EOF
