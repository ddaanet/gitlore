#!/usr/bin/env bash
# One-shot macOS check: the repair take and the bash 3.2 hazards nothing on the
# Linux dev box exercises. Run from anywhere on a Mac with Homebrew's `bash`
# and `bats-core` installed:
#
#   plans/macos-check/run.sh [suite.bats ...]
#
# Everything lands in plans/macos-check/out/ — `report.txt` is the summary to
# hand back, the `*.tap` files beside it are the full streams. Exit status is 0
# when the script ran to the end, whatever the suites said: the report is the
# verdict, not the status.
#
# Suites named on the command line replace the default list, relative to the
# repo root. MODERN_BASH=/path/to/bash (>= 4.4) overrides the Homebrew lookup.
#
# The caller's PATH says nothing about the platform: Homebrew puts its own
# bash, and often GNU sed, grep, find and coreutils, ahead of the system's.
# Every run here therefore gets a PATH of the system directories alone, plus a
# directory of symlinks to exactly the tools the platform lacks — bats, and
# git, jq or shellcheck where /usr/bin has none. EXTRA_TOOLS="a b" adds to that
# list when a suite dies on a missing command; the report names each one
# borrowed.
#
# Its own shebang may resolve to any bash, so it is written for 3.2.
# The `bash -c '…$BASH_VERSION…'` probes expand in the bash they name, not here.
# shellcheck disable=SC2016
set -uo pipefail
unset CDPATH

main() {
  repo="$(cd "$(dirname "$0")/../.." && pwd -P)" || exit 1
  cd "$repo" || exit 1
  out="$repo/plans/macos-check/out"
  rm -rf "$out"
  mkdir -p "$out"
  report="$out/report.txt"
  work="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-macos-check.XXXXXX")" || exit 1
  trap 'rm -rf "$work"' EXIT

  if [ "$#" -gt 0 ]; then suites=("$@"); else suites=("${default_suites[@]}"); fi
  find_bashes
  make_shims
  # From here on a bare name resolves as it would on a Mac with no Homebrew.
  PATH="$work/tools:$system_path"
  export PATH
  {
    environment
    probe_assertions
    probe_override
    run_suites baseline "$work/new" ""
    run_suites mixed    "$work/new" "$work/old"
    run_suites all-old  "$work/old" ""
    probe_cached_runner
    how_to_read
  } 2>&1 | tee "$report"
  echo
  echo "report: $report"
}

# The modern bash drives bats; /bin/bash is the 3.2 every script has to meet.
find_bashes() {
  old_bash=/bin/bash
  new_bash="${MODERN_BASH:-}"
  if [ -z "$new_bash" ]; then
    for c in /opt/homebrew/bin/bash /usr/local/bin/bash; do
      [ -x "$c" ] && { new_bash="$c"; break; }
    done
  fi
  [ -n "$new_bash" ] || new_bash="$(command -v bash)"
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
  for tool in git jq shellcheck ${extra[@]+"${extra[@]}"}; do borrow "$tool" optional; done
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
    echo "macos-check: $tool not found (brew install bats-core)" >&2
    exit 1
  fi
}

environment() {
  section "environment"
  echo "uname:       $(uname -sr)"
  echo "old bash:    $old_bash — $("$old_bash" -c 'echo "$BASH_VERSION"')"
  echo "modern bash: $new_bash — $("$new_bash" -c 'echo "$BASH_VERSION"')"
  echo "bats:        $(command -v bats) — $(bats --version)"
  echo "git:         $(command -v git) — $(git --version)"
  echo "PATH:        $PATH"
  echo "borrowed:   ${borrowed:- none}"
  local tool
  for tool in sed grep find mktemp stat awk cksum jq python3; do
    echo "  $tool -> $(command -v "$tool" || echo MISSING)"
  done
  echo "HEAD:        $(git rev-parse --short HEAD) $(git status --porcelain | wc -l | tr -d ' ') dirty paths"
  # BSD sed rejects `--version`; provoking that error is the detection.
  if sed --version >/dev/null 2>&1; then echo "sed:         GNU (not the BSD tool this check is for)"; else echo "sed:         BSD"; fi
  case "$("$old_bash" -c 'echo "${BASH_VERSINFO[0]}"')" in
    3) ;;
    *) echo "WARNING: $old_bash is not bash 3.x — the old/mixed runs measure nothing about 3.2" ;;
  esac
  if ! "$new_bash" -c '[ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; }'; then
    echo "WARNING: $new_bash is older than 4.4 — set MODERN_BASH"
  fi
}

# The claim in tests/bsd_portability.bats' header and docs/references/testing.md:
# under bash 3.2 a failing non-final `[[ ]]` does not fail a bats test. All three
# tests below SHOULD report `not ok`; an `ok` is a silently passing assertion.
probe_assertions() {
  section "probe: does a failing non-final assertion fail the test?"
  cat > "$work/assert.bats" <<'EOF'
@test "non-final [[ ]] that fails" {
  [[ a == b ]]
  true
}
@test "non-final [ ] that fails" {
  [ a = b ]
  true
}
@test "non-final false" {
  false
  true
}
EOF
  for which in old new; do
    echo "--- bats under $which bash (expected: three 'not ok')"
    PATH="$work/$which:$PATH" bats "$work/assert.bats" 2>&1 | grep -E '^(ok|not ok)'
  done
}

# Proves the mixed run is mixed: the test body's bash and the bash a test execs.
# Expected under `mixed`: test body modern, exec'd bash 3.2.
probe_override() {
  section "probe: GITLORE_TEST_BASH_DIR reaches exec'd scripts only"
  mkdir -p "$work/probe"
  ln -s "$repo/tests/helpers" "$work/probe/helpers"
  cat > "$work/probe/override.bats" <<'EOF'
load helpers/setup
setup() { use_test_bash; }
@test "versions" {
  echo "# test body: $BASH_VERSION" >&3
  echo "# exec'd bash: $(bash -c 'echo "$BASH_VERSION"')" >&3
}
EOF
  PATH="$work/new:$PATH" GITLORE_TEST_BASH_DIR="$work/old" bats "$work/probe/override.bats" 2>&1
}

# run_suites <label> <shim dir for bats> <shim dir for exec'd scripts, or "">
#   baseline  everything under the modern bash: a failure here is macOS/BSD,
#             not 3.2.
#   mixed     assertions under the modern bash (so they are real), exec'd
#             scripts and git hooks under 3.2. The run that counts.
#   all-old   everything under 3.2, which also puts the in-process code there:
#             tests/helpers/fixtures.bash's `${s//…/…}` escapes and the sourced
#             scripts/lib. Its `ok`s are only as good as the assertion probe
#             says; its `not ok`s and crashes are real.
run_suites() {
  local label="$1" bats_shim="$2" script_shim="$3" tap="$out/$1.tap" suite
  section "suites: $label"
  for suite in "${suites[@]}"; do
    [ -f "$suite" ] || { echo "MISSING $suite"; continue; }
    PATH="$bats_shim:$PATH" GITLORE_TEST_BASH_DIR="$script_shim" bats "$suite" > "$work/one.tap" 2>&1
    echo "exit=$? pass=$(grep -c '^ok ' "$work/one.tap") fail=$(grep -c '^not ok ' "$work/one.tap")  $suite"
    { echo "##### $suite"; cat "$work/one.tap"; } >> "$tap"
    awk '/^not ok /{show=1} /^ok /{show=0} show' "$work/one.tap" | sed 's/^/    /'
    grep -q -E '^(ok|not ok) ' "$work/one.tap" || sed 's/^/    /' "$work/one.tap"
  done
  echo "full stream: $tap"
}

# scripts/run-bats-cached.sh with no `--reads-all` and no bats options: every
# optional array is empty, which bash < 4.4 reads as unbound under `set -u`.
# Expected: the first call runs one suite, the second reports it cached.
probe_cached_runner() {
  section "probe: scripts/run-bats-cached.sh under $old_bash, empty arrays"
  printf '@test "ok" { true; }\n' > "$work/one.bats"
  local n
  for n in 1 2; do
    PATH="$work/old:$PATH" "$old_bash" scripts/run-bats-cached.sh "$work/keys" shared-hash -- "$work/one.bats"
    echo "call $n exit=$?"
  done
}

how_to_read() {
  section "how to read this"
  echo "assertion probe: an 'ok' under old bash confirms the header claim in"
  echo "  tests/bsd_portability.bats; three 'not ok' under old bash refutes it."
  echo "mixed: the verdict on the repair take under 3.2. baseline separates a"
  echo "  macOS/BSD failure from a 3.2 one. all-old: trust only its failures."
}

system_path=/usr/bin:/bin:/usr/sbin:/sbin
borrowed=""

section() { printf '\n=== %s\n' "$1"; }

default_suites=(
  tests/merge_memory_repair_arrivals.bats
  tests/merge_memory_repair.bats
  tests/index_compose_repair.bats
  tests/killed_take_repro.bats
  tests/bsd_portability.bats
  tests/run_bats_cached.bats
)

main "$@"
