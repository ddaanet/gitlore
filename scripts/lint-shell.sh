#!/usr/bin/env bash
set -euo pipefail

# Lint every tracked shell script with shellcheck at default severity.
#
# Discovery: tracked files with a shell extension (.sh/.bash/.bats), plus any
# tracked extensionless file whose first line is a shell shebang (git hooks,
# the launcher shim). memory/ is a submodule (its own repo, linted there) and
# docs/ holds markdown with fenced shell examples — both are excluded.

cd "$(git rev-parse --show-toplevel)" || exit 1

# No `\b`: BSD grep's ERE has no word boundary (it spells one `[[:<:]]`), so
# the GNU form would silently discover nothing on macOS. The name is delimited
# by a `/` or blank before and a blank or end-of-line after.
is_shell_shebang() {
  head -1 "$1" | grep -qE '^#!.*(/|[[:blank:]])(ba)?sh([[:blank:]]|$)'
}

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(
  {
    git ls-files -- '*.sh' '*.bash' '*.bats'
    git ls-files | while IFS= read -r f; do
      case "$f" in
        *.sh|*.bash|*.bats) continue ;;
        memory/*|docs/*) continue ;;
      esac
      if [ -f "$f" ] && is_shell_shebang "$f"; then
        printf '%s\n' "$f"
      fi
    done
  } | grep -Ev '^(memory|docs)/' | sort -u
)

if [ "${#files[@]}" -eq 0 ]; then
  echo "lint-shell: no shell files discovered" >&2
  exit 1
fi

# -x follows `source`d files; default severity matches the per-file
# `# shellcheck disable=` convention used across the suite.
shellcheck -x "${files[@]}"
printf 'lint-shell: %d files clean\n' "${#files[@]}"
