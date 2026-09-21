#!/usr/bin/env bash
# The unit suite as a Mac with no Homebrew on PATH would meet it: bats and the
# test bodies under a modern bash, so a failing non-final `[[ ]]` is a real
# failure, and every script and git hook a test execs under the system's bash
# 3.2 with the BSD tools. Needs Homebrew's `bash` and `bats-core`:
#
#   scripts/test-macos.sh [suite.bats ...]
#
# Exit status is bats' own, so this can gate. Suites named on the command line
# replace the default — every `tests/*.bats` that is not an integration suite.
# It records no gate sentinel: `test-unit`'s hash does not know which bash ran
# the scripts, and a pass from here must not stand in for one from there.
#
#   MODERN_BASH=/path/to/bash  (>= 4.4) overrides the Homebrew lookup.
#   OLD_BASH=/path/to/bash     stands in for /bin/bash; without it, a /bin/bash
#                              that is not 3.x is refused, since the run would
#                              measure nothing about 3.2.
#   EXTRA_TOOLS="a b"          borrows more tools when a suite dies on a
#                              missing command.
#
# The caller's PATH says nothing about the platform: Homebrew puts its own
# bash, and often GNU sed, grep, find and coreutils, ahead of the system's. The
# run gets the system directories alone, plus symlinks to exactly the tools
# they lack; the header of the output names each one borrowed.
# `plans/macos-check/run.sh` is the one-shot diagnostic this grew out of, with
# the probes and the three-way comparison this leaves out.
#
# Its own shebang may resolve to any bash, so it is written for 3.2.
# The `bash -c '…$BASH_VERSINFO…'` probes expand in the bash they name, not here.
# shellcheck disable=SC2016
set -uo pipefail
unset CDPATH

main() {
  repo="$(cd "$(dirname "$0")/.." && pwd -P)" || exit 1
  cd "$repo" || exit 1
  work="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-test-macos.XXXXXX")" || exit 1
  trap 'rm -rf "$work"' EXIT

  if [ "$#" -gt 0 ]; then suites=("$@"); else default_suites; fi
  find_bashes
  make_shims
  # From here on a bare name resolves as it would on a Mac with no Homebrew.
  PATH="$work/tools:$system_path"
  export PATH
  environment

  PATH="$work/new:$PATH" GITLORE_TEST_BASH_DIR="$work/old" \
    scripts/run-bats.sh "${suites[@]}"
}

# A glob, never a hand list, for `test-unit`'s reason: a list drifts and
# orphans suites.
default_suites() {
  local suite
  suites=()
  for suite in tests/*.bats; do
    case "$suite" in tests/integration_*.bats) continue ;; esac
    [ -f "$suite" ] && suites+=("$suite")
  done
  [ "${#suites[@]}" -gt 0 ] || { echo "test-macos: no suites matched tests/*.bats" >&2; exit 1; }
}

# The modern bash drives bats; the old one is the 3.2 every script has to meet.
find_bashes() {
  local c
  old_bash="${OLD_BASH:-/bin/bash}"
  if [ -z "${OLD_BASH:-}" ] && [ "$("$old_bash" -c 'echo "${BASH_VERSINFO[0]}"')" != 3 ]; then
    echo "test-macos: $old_bash is not bash 3.x, so this run would measure nothing about 3.2 (OLD_BASH overrides)" >&2
    exit 1
  fi
  new_bash="${MODERN_BASH:-}"
  if [ -z "$new_bash" ]; then
    for c in /opt/homebrew/bin/bash /usr/local/bin/bash; do
      [ -x "$c" ] && { new_bash="$c"; break; }
    done
  fi
  [ -n "$new_bash" ] || new_bash="$(command -v bash)"
  if ! "$new_bash" -c '[ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; }'; then
    echo "test-macos: $new_bash is older than 4.4 — brew install bash, or set MODERN_BASH" >&2
    exit 1
  fi
}

# A directory holding only `bash`, to put first on PATH: `#!/usr/bin/env bash`
# then resolves to the one chosen, for bats and for the scripts alike.
make_shims() {
  mkdir -p "$work/old" "$work/new" "$work/tools"
  ln -s "$old_bash" "$work/old/bash"
  ln -s "$new_bash" "$work/new/bash"
  borrow bats required
  local tool extra
  IFS=' ' read -r -a extra <<< "${EXTRA_TOOLS:-}"
  # `${a[@]+…}`: an empty array is unbound to `set -u` before bash 4.4.
  for tool in git jq shellcheck just ${extra[@]+"${extra[@]}"}; do borrow "$tool" optional; done
}

# borrow <tool> <required|optional> — link a tool the system directories lack
# from wherever the caller's PATH has it. Runs before PATH is narrowed.
borrow() {
  local tool="$1" found
  if PATH="$system_path" command -v "$tool" >/dev/null; then return 0; fi
  if found="$(command -v "$tool")"; then
    ln -s "$found" "$work/tools/$tool"
    borrowed="$borrowed $tool=$found"
  elif [ "$2" = required ]; then
    echo "test-macos: $tool not found (brew install bats-core)" >&2
    exit 1
  fi
}

environment() {
  echo "test-macos: $(uname -sr), ${#suites[@]} suites"
  echo "  old bash:    $old_bash — $("$old_bash" -c 'echo "$BASH_VERSION"')"
  echo "  modern bash: $new_bash — $("$new_bash" -c 'echo "$BASH_VERSION"')"
  echo "  bats:        $(command -v bats) — $(bats --version)"
  echo "  borrowed:   ${borrowed:- none}"
  # BSD sed rejects `--version`; provoking that error is the detection.
  if sed --version >/dev/null 2>&1; then echo "  sed:         GNU (not the BSD tool this check is for)"; else echo "  sed:         BSD"; fi
}

system_path=/usr/bin:/bin:/usr/sbin:/sbin
borrowed=""

main "$@"
