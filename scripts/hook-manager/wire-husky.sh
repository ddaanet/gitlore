#!/usr/bin/env bash
set -euo pipefail

[ -d .husky ] || { echo "wire-husky: no .husky directory" >&2; exit 1; }

# pre-commit is not wired (D58): a memory commit is the agent's own act.
f=".husky/pre-push"
if [ ! -f "$f" ]; then
  cat > "$f" <<EOF2
#!/usr/bin/env sh
EOF2
  chmod +x "$f"
fi
# NOTE: the exec line replaces the husky shell process with the gitlore
# wrapper. Any husky steps written after this block will never execute.
# Husky itself calls this hook last, so that is fine for standard setups —
# but users with additional steps after the gitlore block should be aware.
if ! grep -q '# gitlore: managed' "$f"; then
  # Common-dir anchor (D11): resolves from every worktree, incl. linked ones.
  # shellcheck disable=SC2016  # $(...) and $@ are literal; the hook expands them
  exec_line='exec "$(git rev-parse --git-common-dir)/gitlore-pre-push" "$@"'
  { printf '\n# gitlore: managed\n'; printf '%s\n' "$exec_line"; } >> "$f"
fi

mkdir -p .claude
printf 'npx husky\n' > .claude/gitlore-hook-setup
