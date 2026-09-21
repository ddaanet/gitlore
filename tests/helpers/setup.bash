#!/usr/bin/env bash
# Common bats setup. Source from each .bats file with: `load helpers/setup`.
set -euo pipefail

# Every entry point under scripts/ opens with this, and the fixtures and suites
# carry the same `$(cd … && pwd)` pattern: with CDPATH set in the environment,
# `cd` echoes its resolved target on stdout and the capture takes two lines.
unset CDPATH

# The suites assert with `[[ … == *glob* ]]`, and under bash < 4.1 a failing
# non-final `[[ ]]` does not fail a bats test, so a run there reports green for
# assertions it never checked. Refused here, where every suite loads, rather
# than converted: `[ ]` has no glob match to convert them to.
require_assertion_bash() {
  local major="$1" minor="$2"
  if [ "$major" -gt 4 ] || { [ "$major" -eq 4 ] && [ "$minor" -ge 1 ]; }; then return 0; fi
  echo "gitlore tests: bats is running under bash $major.$minor, where a failing non-final [[ ]] passes silently." >&2
  echo "Run bats with bash >= 4.1; on macOS, scripts/test-macos.sh does that while the scripts under test still meet the system's 3.2." >&2
  return 1
}
require_assertion_bash "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/.."
export PLUGIN_ROOT

# Trigger strings shared between a negative assertion and the positive that
# pins the wording. Loaded here so every suite has them without a second `load`.
# shellcheck source=tests/helpers/triggers.bash
source "${BATS_TEST_DIRNAME}/helpers/triggers.bash"

setup_tmp_repo() {
  # A hook reads its payload with `payload=$(cat)`, and a test that invokes one
  # without piping anything into it inherits bats' own stdin — a socket or a
  # terminal under an interactive run, never a closed pipe — so that `cat`
  # blocks until the harness dies. `exec` rather than a per-call `</dev/null`:
  # the redirection has to hold for every invocation in the body, and bats runs
  # setup and the test in one process, so it does not leak to the next test. A
  # test that means to feed a payload still pipes one, which overrides this.
  exec 0</dev/null
  use_test_bash
  TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-test.XXXXXX")"
  export TMP_REPO
  cd "$TMP_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name  "Test"
}

# A macOS check drives bats with a modern bash while the scripts under test
# have to meet the system's 3.2. A directory holding the `bash` of the caller's
# choosing goes first on PATH, so every `#!/usr/bin/env bash` and `bash "$CMD"`
# a test execs resolves there. Called from `setup`, never at load time: bats
# sources a suite before it spawns each test through `env bash`, and a PATH
# exported that early puts the test body itself under the chosen bash.
# Libraries sourced below still run in the test's own bash.
use_test_bash() {
  [ -n "${GITLORE_TEST_BASH_DIR:-}" ] || return 0
  PATH="$GITLORE_TEST_BASH_DIR:$PATH"
  export PATH
}

teardown_tmp_repo() {
  if [ -n "${TMP_REPO:-}" ] && [ -d "$TMP_REPO" ]; then
    rm -rf "$TMP_REPO"
  fi
}

# Load every script under scripts/lib so library functions are in scope.
# The glob may expand to nothing if the directory doesn't exist yet; that's fine.
shopt -s nullglob
for f in "$PLUGIN_ROOT"/scripts/lib/*.sh; do
  # shellcheck disable=SC1090
  source "$f"
done
shopt -u nullglob
