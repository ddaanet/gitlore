#!/usr/bin/env bash
# wire-direct.sh — install .git/hooks/pre-commit and pre-push stubs directly.
#
# Exec semantics: the appended `exec .git/gitlore-<hook>` replaces the shell
# process, so any lines added AFTER the gitlore block in an existing hook will
# not run. Content already present BEFORE the block runs normally.
set -euo pipefail

for hook in pre-commit pre-push; do
  f=".git/hooks/$hook"
  if [ -f "$f" ] && grep -q '# gitlore: managed' "$f"; then
    # Already wired — skip to preserve idempotency.
    continue
  fi
  if [ -f "$f" ]; then
    cat >> "$f" <<EOF

# gitlore: managed
exec .git/gitlore-$hook "\$@"
EOF
  else
    cat > "$f" <<EOF
#!/usr/bin/env sh
# gitlore: managed
exec .git/gitlore-$hook "\$@"
EOF
  fi
  chmod +x "$f"
done

mkdir -p .claude
printf 'direct\n' > .claude/gitlore-hook-setup
