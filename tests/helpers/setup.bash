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
  # `exit`, not `return`: bats acts on what a `load`ed file returns only from
  # 1.13 — under 1.11 a returned refusal prints its reason to stderr and every
  # test still reports ok. A guard that enforces a floor cannot be enforceable
  # only above it, so it exits, which fails the load on every bats.
  exit 1
}
require_assertion_bash "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"

# Before 1.13, a merged `run` leaves `$stderr` holding whatever an earlier
# `run --separate-stderr` captured; from 1.13 it unsets the pair. A suite that
# asserts on `$stderr` after a merged `run` therefore reads a stale capture and
# passes under the older bats, and dies on an unbound variable under the newer.
# Refused rather than accommodated: the repo pins no tool versions, so the floor
# is what keeps one machine's green from being another's red. Debian's package
# is 1.11 and cannot satisfy this — `brew install bats-core` or `npm i -g bats`.
require_bats_version() {
  local version="$1" major minor
  major="${version%%.*}"
  minor="${version#*.}"; minor="${minor%%.*}"
  case "$major$minor" in *[!0-9]*|'') major=0; minor=0 ;; esac
  if [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 13 ]; }; then return 0; fi
  echo "gitlore tests: bats reports version '$version'; the suites need >= 1.13." >&2
  echo "Below it a merged \`run\` leaves \$stderr set from an earlier --separate-stderr run, so an assertion on it passes against a stale capture." >&2
  echo "brew install bats-core, or npm i -g bats (Debian's package is 1.11)." >&2
  exit 1   # see require_assertion_bash: a `return` refuses nothing under 1.11
}
require_bats_version "${BATS_VERSION:-}"

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
  # `pwd -P`, not the raw mktemp output: on macOS `$TMPDIR` is a symlinked
  # `/var/folders/…` path, and git and the scripts under test report the
  # physical `/private/var/…` one. A fixture that keeps the logical form makes
  # every `== *"$TMP_REPO"/…*` assertion compare two spellings of one path.
  TMP_REPO="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gitlore-test.XXXXXX")" && pwd -P)"
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

# A file's permission bits in octal. The GNU form is tried first and its
# failure is the probe: BSD/macOS stat spells the same field `-f '%Lp'`.
file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
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
