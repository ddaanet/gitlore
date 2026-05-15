#!/usr/bin/env bash
set -euo pipefail

[ -d .husky ] || { echo "wire-husky: no .husky directory" >&2; exit 1; }

for hook in pre-commit pre-push; do
  f=".husky/$hook"
  if [ ! -f "$f" ]; then
    cat > "$f" <<EOF
#!/usr/bin/env sh
EOF
    chmod +x "$f"
  fi
  # NOTE: the exec line replaces the husky shell process with the gitlore
  # wrapper. Any husky steps written after this block will never execute.
  # Husky itself calls this hook last, so that is fine for standard setups —
  # but users with additional steps after the gitlore block should be aware.
  if ! grep -q '# gitlore: managed' "$f"; then
    cat >> "$f" <<EOF

# gitlore: managed
exec .git/gitlore-$hook "\$@"
EOF
  fi
done

mkdir -p .claude
printf 'npx husky\n' > .claude/gitlore-hook-setup
