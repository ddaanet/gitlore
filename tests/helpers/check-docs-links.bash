#!/usr/bin/env bash
# Shared fixtures for the check-docs-links suites: the throwaway repo each
# case plants docs/ and docs/references/ content into, and the planters that
# write the hub, the decisions index, and a reference node.
# Planted file contents carry backticked spans and literal link syntax on
# purpose — they are fixtures for the checker to read, not expansions this
# suite wants.
# shellcheck disable=SC2016

CHECKER=
export CHECKER

setup() {
  setup_tmp_repo
  CHECKER="$PLUGIN_ROOT/scripts/check-docs-links.py"
  mkdir -p docs/references
  # The hub itself: the checker requires it, but reads no conclusion from it.
  printf '# gitlore Design Document\n\nSee [decisions](decisions.md).\n' \
    > docs/design.md
}
teardown() { teardown_tmp_repo; }

# The decisions index. Args are body lines appended after a fixed preamble.
plant_decisions() {
  {
    printf '# gitlore Design Decisions\n\n'
    printf '## Design Decisions\n\n'
    printf '%s\n' "$@"
  } > docs/decisions.md
}

# A reference node. $1 = basename under docs/references/, rest are body lines.
plant_ref() {
  local name="$1"
  shift
  printf '%s\n' "$@" > "docs/references/$name"
}
