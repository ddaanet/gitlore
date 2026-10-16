#!/usr/bin/env bash
set -euo pipefail
unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below

PLUGIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

# Anchor wrappers in the git COMMON dir (shared across all worktrees), not a
# literal `.git/` — in a linked worktree `.git` is a gitlink *file*, so a literal
# path fails to write. `git rev-parse --git-common-dir` resolves to `.git` in the
# main worktree and the shared `<main>/.git` in a linked one, so a single emission
# is reachable and executable from every worktree (D11).
common_dir=$(git rev-parse --git-common-dir)

gitlore_emit_hook_wrapper "$common_dir/gitlore-pre-push" pre-push

# Stub, not a wrapper: a tracked hook-manager config may still name this file.
cat > "$common_dir/gitlore-pre-commit" <<'EOF'
#!/usr/bin/env sh
# Kept so hook-manager configs that still name this file keep working; it does nothing.
exit 0
EOF
chmod +x "$common_dir/gitlore-pre-commit"
