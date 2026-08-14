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
# lines AFTER the gitlore block in an existing hook will not run. Refuses
# instead of appending when an existing hook body already execs, since that
# would make the appended gitlore block itself unreachable.
set -euo pipefail

for hook in pre-commit pre-push; do
  f=$(git rev-parse --git-path "hooks/$hook")
  mkdir -p "$(dirname "$f")"
  if [ -f "$f" ] && grep -q '# gitlore: managed' "$f"; then
    continue
  fi
  # `exec` replaces the process, so a gitlore line appended after an existing
  # `exec` in the hook body would be unreachable dead code. Detection is a
  # heuristic (a real shell parser is out of scope), matching the brief's own
  # suggested check: any non-comment line whose first token is `exec`.
  if [ -f "$f" ] && grep -qE '^[[:space:]]*exec([[:space:]]|$)' "$f"; then
    {
      echo "gitlore: '$f' already contains an 'exec' — appending would be unreachable dead code."
      echo "Interpose the gitlore line before that exec yourself (or drop 'exec' there and chain '|| exit 1'), then re-run /gitlore:install:"
      echo
      echo "  exec \"\$(git rev-parse --git-common-dir)/gitlore-$hook\" \"\$@\""
    } >&2
    exit 1
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
