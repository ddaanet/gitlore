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
# unmerged path is listed once per index stage. A path the index still lists
# but the working tree has lost is skipped: this lints the tree as it stands.
files=()
while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  case "$f" in
    memory/*|docs/*) continue ;;
    *.sh|*.bash|*.bats) ;;
    *) is_shell_shebang "$f" || continue ;;
  esac
  files+=("$f")
done < <(git ls-files -z --cached --others --exclude-standard | sort -zu)

if [ "${#files[@]}" -eq 0 ]; then
  echo "lint-shell: no shell files discovered" >&2
  exit 1
fi

# A file whose key is in the cache passed under this shellcheck with exactly
# these contents, its own and those of everything it sources, and is not linted
# again; lint-cache-keys.py says what a key covers. Only passes are recorded,
# and the cache is rewritten from this run's keys, so it prunes itself.
# `GITLORE_GATE_FORCE` lints everything, as it does for the gate around this.
# Under the gitdir for the gate sentinels' reason: bookkeeping in the working
# tree would show up in `git status`.
cache="$(git rev-parse --git-path gitlore/lint-cache)"
mkdir -p "$(dirname "$cache")"
[ -f "$cache" ] || : > "$cache"
tool_version="$(shellcheck --version)"

keys=()
misses=()
while IFS= read -r -d '' key && IFS= read -r -d '' f; do
  keys+=("$key")
  if [ -n "${GITLORE_GATE_FORCE:-}" ] || ! grep -Fxq -- "$key" "$cache"; then
    misses+=("$f")
  fi
done < <(printf '%s\0' "${files[@]}" | "$(dirname "$0")/lint-cache-keys.py" "$tool_version")

if [ "${#keys[@]}" -ne "${#files[@]}" ]; then
  echo "lint-shell: lint-cache-keys.py keyed ${#keys[@]} of ${#files[@]} files" >&2
  exit 1
fi

# -x follows `source`d files; default severity matches the per-file
# `# shellcheck disable=` convention used across the suite. One invocation
# gives one verdict for every miss, so a failure records none of them.
if [ "${#misses[@]}" -gt 0 ]; then
  shellcheck -x "${misses[@]}"
fi
printf '%s\n' "${keys[@]}" > "$cache"
printf 'lint-shell: %d files clean (%d cached)\n' "${#files[@]}" "$(( ${#files[@]} - ${#misses[@]} ))"
