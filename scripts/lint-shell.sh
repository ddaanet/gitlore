#!/usr/bin/env bash
set -euo pipefail

# Lint every shell script in the working tree with shellcheck at default
# severity.
#
# Discovery: tracked files and untracked, non-ignored ones — the set
# `gate-inputs-hash` in the justfile enumerates, so a brand-new file that moves
# the `lint` gate's hash is also a file this linted. Of those, the ones with a
# shell extension (.sh/.bash/.bats), plus any extensionless file whose first
# line is a shell shebang (git hooks, the launcher shim). memory/ is a
# submodule (its own repo, linted there) and docs/ holds markdown with fenced
# shell examples — both are excluded.

cd "$(git rev-parse --show-toplevel)" || exit 1

# No `\b`: BSD grep's ERE has no word boundary (it spells one `[[:<:]]`), so
# the GNU form would silently discover nothing on macOS. The name is delimited
# by a `/` or blank before and a blank or end-of-line after.
is_shell_shebang() {
  head -1 "$1" | grep -qE '^#!.*(/|[[:blank:]])(ba)?sh([[:blank:]]|$)'
}

# NUL-delimited, so no filename can split a record. `sort -zu` because an
# unmerged path is listed once per index stage.
files=()
while IFS= read -r -d '' f; do
  case "$f" in
    memory/*|docs/*) continue ;;
    *.sh|*.bash|*.bats) ;;
    *) { [ -f "$f" ] && is_shell_shebang "$f"; } || continue ;;
  esac
  files+=("$f")
done < <(git ls-files -z --cached --others --exclude-standard | sort -zu)

if [ "${#files[@]}" -eq 0 ]; then
  echo "lint-shell: no shell files discovered" >&2
  exit 1
fi

# -x follows `source`d files; default severity matches the per-file
# `# shellcheck disable=` convention used across the suite.
shellcheck -x "${files[@]}"
printf 'lint-shell: %d files clean\n' "${#files[@]}"
