#!/usr/bin/env bats
# scripts/test-macos.sh against tiny real suites. The platform cannot be faked
# from Linux, so what is pinned is the wiring: bats' verdict becomes the exit
# status, and the stand-in for /bin/bash is the bash a test execs while the
# test body stays under the modern one. `OLD_BASH` is a wrapper that logs each
# start and hands over to the real bash.

# The planted bodies are single-quoted on purpose: they expand in the suite
# that runs them, not in this one.
# shellcheck disable=SC2016
load helpers/setup

setup() {
  setup_tmp_repo
  OLD_LOG="$TMP_REPO/old-bash.log"
  real_bash="$(command -v bash)"
  cat > "$TMP_REPO/old-bash" <<EOF
#!/bin/sh
echo started >> "$OLD_LOG"
exec "$real_bash" "\$@"
EOF
  chmod +x "$TMP_REPO/old-bash"
}
teardown() { teardown_tmp_repo; }

# A suite that opts into the chosen bash the way every real one does, through
# `setup`, then runs <body>. `helpers` is linked beside it because `setup.bash`
# finds its siblings, and the plugin root, relative to the suite that loads it.
plant() {
  mkdir -p "$TMP_REPO/t"
  [ -e "$TMP_REPO/t/helpers" ] || ln -s "$PLUGIN_ROOT/tests/helpers" "$TMP_REPO/t/helpers"
  # `printf`, not a heredoc: bats rewrites every line that opens with its test
  # keyword, this file's heredocs included.
  printf '%s\n' 'load helpers/setup' 'setup() { use_test_bash; }' \
    "@""test \"$1\" {" "  $2" '}' > "$TMP_REPO/t/$1"
}

macos() {
  OLD_BASH="$TMP_REPO/old-bash" MODERN_BASH="$real_bash" \
    "$PLUGIN_ROOT/scripts/test-macos.sh" "$@"
}

@test "test-macos.sh is discoverable and executable" {
  [ -x "$PLUGIN_ROOT/scripts/test-macos.sh" ]
}

@test "a passing suite exits 0 and the header names both bashes" {
  plant ok.bats true
  run macos "$TMP_REPO/t/ok.bats"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  grep -qF "old bash:    $TMP_REPO/old-bash" <<< "$output"
  grep -qF "modern bash: $real_bash" <<< "$output"
  grep -qF "bats: 1 passed, 0 failed" <<< "$output"
}

@test "a failing suite is the exit status, not a line in a report" {
  plant bad.bats false
  run macos "$TMP_REPO/t/bad.bats"
  [ "$status" -ne 0 ]
  grep -qF "bats: 0 passed, 1 failed" <<< "$output"
}

@test "the old bash runs what a test execs, and not the test body" {
  # Absence of the log proves nothing: bats execs `bash` for its own purposes
  # once `setup` has moved PATH. The body names the bash it runs under instead.
  plant body.bats 'case "$BASH" in */new/bash) ;; *) echo "body under $BASH" >&2; false ;; esac'
  run macos "$TMP_REPO/t/body.bats"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }

  # The log alone would be bats' own execs; the body also names what a bare
  # `bash` resolves to before it execs one.
  plant execs.bats 'case "$(command -v bash)" in */old/bash) bash -c true ;; *) false ;; esac'
  run macos "$TMP_REPO/t/execs.bats"
  [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
  [ -s "$OLD_LOG" ]
}

@test "a /bin/bash that is not 3.x is refused unless OLD_BASH names a stand-in" {
  [ "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')" != 3 ] || skip "/bin/bash is 3.x here"
  plant ok.bats true
  run env -u OLD_BASH "$PLUGIN_ROOT/scripts/test-macos.sh" "$TMP_REPO/t/ok.bats"
  [ "$status" -ne 0 ]
  grep -qF "is not bash 3.x" <<< "$output"
}
