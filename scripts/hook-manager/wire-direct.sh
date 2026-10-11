#!/usr/bin/env bash
# wire-direct.sh — install the pre-push stub in the shared hooks dir.
#
# Gitlink-aware (D11): the hook FILE path resolves via `git rev-parse --git-path
# hooks/<hook>` (the shared common-dir hooks file — a literal `.git/hooks/...`
# breaks in a linked worktree), and the stub EXECs the wrapper via
# `$(git rev-parse --git-common-dir)/gitlore-<hook>` so it resolves from every
# worktree, including session-less ones.
#
# pre-commit is not wired (D58): a memory commit is the agent's own act. A
# pre-commit file this script wrote in an earlier version is removed or has its
# gitlore block stripped; any other pre-commit hook is left byte-for-byte alone.
#
# Exec semantics: the appended `exec ...` replaces the shell process, so any
# lines AFTER the gitlore block in an existing hook will not run. Refuses
# instead of appending when an existing hook body already execs, since that
# would make the appended gitlore block itself unreachable.
set -euo pipefail

# shellcheck disable=SC2016  # $(...) and $@ are literal; the hook expands them
exec_line='exec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"'

# Retire the pre-commit file an earlier version wrote. Compared byte for byte
# (the trailing `x` keeps command substitution from eating a final newline).
f=$(git rev-parse --git-path hooks/pre-commit)
if [ -f "$f" ]; then
  shim=$(printf '#!/usr/bin/env sh\n# gitlore: managed\n%s\n' "$exec_line"; printf x)
  shim=${shim%x}
  content=$(cat "$f"; printf x)
  content=${content%x}
  block=$(printf '\n# gitlore: managed\n%s\n' "$exec_line"; printf x)
  block=${block%x}
  if [ "$content" = "$shim" ]; then
    rm -f "$f"
  elif [ "${content%"$block"}" != "$content" ]; then
    # Strip exactly the block; truncating in place keeps the file's mode.
    printf '%s' "${content%"$block"}" > "$f"
  fi
fi

f=$(git rev-parse --git-path hooks/pre-push)
mkdir -p "$(dirname "$f")"
if [ -f "$f" ] && grep -q '# gitlore: managed' "$f"; then
  :
# `exec` replaces the process, so a gitlore line appended after an existing
# `exec` in the hook body would be unreachable dead code. Detection is a
# heuristic (a real shell parser is out of scope), matching the brief's own
# suggested check: any non-comment line whose first token is `exec`.
elif [ -f "$f" ] && grep -qE '^[[:space:]]*exec([[:space:]]|$)' "$f"; then
  {
    echo "gitlore: '$f' already contains an 'exec' — appending would be unreachable dead code."
    echo "Interpose the gitlore line before that exec yourself (or drop 'exec' there and chain '|| exit 1'), then re-run /gitlore:install:"
    echo
    echo "  exec \"\$(git rev-parse --git-common-dir)/gitlore-pre-push\" \"\$@\""
  } >&2
  exit 1
else
  # shellcheck disable=SC2016  # $(...) and $@ are literal; the hook expands them
  exec_push='exec "$(git rev-parse --git-common-dir)/gitlore-pre-push" "$@"'
  if [ -f "$f" ]; then
    { printf '\n# gitlore: managed\n'; printf '%s\n' "$exec_push"; } >> "$f"
  else
    { printf '#!/usr/bin/env sh\n# gitlore: managed\n'; printf '%s\n' "$exec_push"; } > "$f"
  fi
  chmod +x "$f"
fi

mkdir -p .claude
printf 'direct\n' > .claude/gitlore-hook-setup
