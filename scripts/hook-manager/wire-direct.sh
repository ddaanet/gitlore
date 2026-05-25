#!/usr/bin/env bash
# wire-direct.sh — install pre-commit/pre-push stubs in the shared hooks dir.
#
# Gitlink-aware (D11): the hook FILE path resolves via `git rev-parse --git-path
# hooks/<hook>` (the shared common-dir hooks file — a literal `.git/hooks/...`
# breaks in a linked worktree), and the stub EXECs the wrapper via
# `$(git rev-parse --git-common-dir)/gitlore-<hook>` so it resolves from every
# worktree, including session-less ones.
#
# Exec semantics: the appended `exec ...` replaces the shell process, so any
# lines AFTER the gitlore block in an existing hook will not run.
set -euo pipefail

for hook in pre-commit pre-push; do
  f=$(git rev-parse --git-path "hooks/$hook")
  mkdir -p "$(dirname "$f")"
  if [ -f "$f" ] && grep -q '# gitlore: managed' "$f"; then
    continue
  fi
  # Build the exec line: hook name expands now; `$(...)` and `$@` stay literal so
  # they expand when the hook runs.
  exec_line="exec \"\$(git rev-parse --git-common-dir)/gitlore-$hook\" \"\$@\""
  if [ -f "$f" ]; then
    { printf '\n# gitlore: managed\n'; printf '%s\n' "$exec_line"; } >> "$f"
  else
    { printf '#!/usr/bin/env sh\n# gitlore: managed\n'; printf '%s\n' "$exec_line"; } > "$f"
  fi
  chmod +x "$f"
done

mkdir -p .claude
printf 'direct\n' > .claude/gitlore-hook-setup
