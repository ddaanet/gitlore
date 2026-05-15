#!/usr/bin/env bash
# Common bats setup. Source from each .bats file with: `load helpers/setup`.
set -euo pipefail

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/.."
export PLUGIN_ROOT

setup_tmp_repo() {
  TMP_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-test.XXXXXX")"
  export TMP_REPO
  cd "$TMP_REPO"
  git init -q -b main
  git config user.email "test@example.com"
  git config user.name  "Test"
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
