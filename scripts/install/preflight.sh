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

if [ -z "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
  cat >&2 <<'EOF'
gitlore: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is not set.
gitlore: /gitlore:resolve requires it to dispatch the memory-merger sub-agent.
gitlore: Continuing install — set it before semantic merge is needed:
gitlore:   export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
EOF
fi

exit 0
