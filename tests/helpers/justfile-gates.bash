#!/usr/bin/env bash
# Shared fixtures for the justfile-gate suites: a per-test scratch directory
# for stubs, and the wrappers that read a gate's declared inputs out of the
# shipped justfile rather than a transcription of it. The sentinel functions
# themselves are the toolkit's (`plugin-dev/gates.just`) and are tested there.

setup() {
  command -v just > /dev/null || {
    echo "just is not on PATH; the gate recipes cannot be inspected" >&2
    return 1
  }
  # Where a test puts the stub it hands a recipe in place of a real tool.
  STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-justfile-stub.XXXXXX")"
}

teardown() {
  if [ -n "${STUB_DIR:-}" ]; then
    rm -rf "$STUB_DIR"
  fi
}

# `env -C` is GNU-only, so every invocation below goes through a subshell cd.
just_here() {
  ( cd "$PLUGIN_ROOT" && just "$@" )
}

# A gate's `sentinel-guard` line as its shell receives it, rebuilt from just's
# own dump so the assertion reads the shipped recipe rather than a copy of it.
# Body segments come back as literal strings and as interpolations naming a
# variable; `just --evaluate` supplies the latter. No segment here spans a
# newline, which is what lets the two kinds travel as one line each.
guard_line() {
  local segments seg rendered=""
  segments=$(
    just_here --dump --dump-format json | jq -r --arg r "$1" '
      .recipes[$r].body[]
      | select((.[0] | type) == "string" and (.[0] | startswith("sentinel-guard ")))
      | .[]
      | if type == "string" then "L" + .
        # An interpolation is `["variable", name]` up to just 1.45 and
        # `[["variable", name]]` from 1.46.
        elif (.[0] | type) == "array" then "V" + .[0][1]
        else "V" + .[1] end
    '
  ) || return 1
  while IFS= read -r seg || [ -n "$seg" ]; do
    case "$seg" in
      L*) rendered="$rendered${seg#L}" ;;
      # A name that does not evaluate would render as nothing, and a guard line
      # with no pathspec enumerates the whole tree — every assertion on it
      # would then pass or fail for the wrong reason.
      V*) rendered="$rendered$(just_here --evaluate "${seg#V}")" || return 1 ;;
    esac
  done <<< "$segments"
  printf '%s\n' "$rendered"
}

# The paths a gate's declared inputs actually enumerate, in this repo.
guard_input_files() {
  local line
  line=$(guard_line "$1") || return 1
  # The recipe's own quoting decides the word boundaries, so the shell that
  # splits them has to be the shell — the gate's arguments carry an exclude
  # pathspec whose parentheses and glob are protected by quotes in the justfile.
  eval "set -- $line"
  shift 2
  git -C "$PLUGIN_ROOT" ls-files --cached --others --exclude-standard -- "$@"
}
