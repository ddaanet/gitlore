#!/usr/bin/env bash
# Shared fixture for the tests/index_compose*.bats suites: the bullet-block
# writer more than one of those suites calls.

# Replace $1's bullet block with the remaining args, preamble and trailer intact.
set_bullets() { local f="$1"; shift; printf '%s\n' "$@" | gitlore_compose_write "$f" >/dev/null; }
