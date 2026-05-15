#!/usr/bin/env bash
set -euo pipefail

write_wrapper() {
  local hook="$1"
  local out=".git/gitlore-$hook"
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
