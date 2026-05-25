#!/usr/bin/env bash
set -euo pipefail

# Anchor wrappers in the git COMMON dir (shared across all worktrees), not a
# literal `.git/` — in a linked worktree `.git` is a gitlink *file*, so a literal
# path fails to write. `git rev-parse --git-common-dir` resolves to `.git` in the
# main worktree and the shared `<main>/.git` in a linked one, so a single emission
# is reachable and executable from every worktree (D11).
common_dir=$(git rev-parse --git-common-dir)

write_wrapper() {
  local hook="$1"
  local out="$common_dir/gitlore-$hook"
  cat > "$out" <<EOF
#!/usr/bin/env sh
HOOKS_DIR=\$(git config gitlore.hooksDir 2>/dev/null)
if [ -z "\$HOOKS_DIR" ]; then
  echo "gitlore skipped: hooks not installed." >&2
  echo "Install the gitlore plugin from the Claude Code marketplace, then start Claude Code in this repo." >&2
  exit 0
fi
exec "\$HOOKS_DIR/$hook" "\$@"
EOF
  chmod +x "$out"
}

write_wrapper pre-commit
write_wrapper pre-push
