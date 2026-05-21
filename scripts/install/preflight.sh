#!/usr/bin/env bash
# Exit 0 if gh is available and authenticated; non-zero with a fix-up
# message on stderr otherwise. Must do no destructive work.
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  cat >&2 <<'EOF'
gitlore: 'gh' CLI not found. Install it from https://cli.github.com/, then re-run /gitlore:install.
EOF
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  cat >&2 <<'EOF'
gitlore: 'gh' is not authenticated. Run 'gh auth login', then re-run /gitlore:install.
EOF
  exit 1
fi

exit 0
