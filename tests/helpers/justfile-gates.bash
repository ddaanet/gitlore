#!/usr/bin/env bash
# Shared fixtures for the justfile-gate suites: the throwaway repo the gate
# sentinel tests run against, and the wrappers that drive it through the
# shipped prolog rather than a transcription of it.

setup() {
  command -v just > /dev/null || {
    echo "just is not on PATH; the gate recipes cannot be inspected" >&2
    return 1
  }
  # `bats` reduced to an echo of its arguments, so a recipe can be asked what it
  # WOULD run without running it. Discovery is the thing under test.
  STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-justfile-stub.XXXXXX")"
  cat > "$STUB_DIR/bats" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
  chmod +x "$STUB_DIR/bats"
}

teardown() {
  if [ -n "${STUB_DIR:-}" ]; then
    rm -rf "$STUB_DIR"
  fi
  if [ -n "${GATE_REPO:-}" ]; then
    rm -rf "$GATE_REPO"
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

# A throwaway repo plus the gate helpers as the recipes actually get them:
# `just --evaluate` hands back the exact prolog text every shebang expands to,
# so these exercise the shipped code rather than a transcription of it.
setup_gate_repo() {
  GATE_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-gate-repo.XXXXXX")"
  PROLOG="$GATE_REPO/prolog.bash"
  { printf '#!'; just_here --evaluate bash_prolog; } > "$PROLOG"
  git -C "$GATE_REPO" init -q
  git -C "$GATE_REPO" config user.email t@example.com
  git -C "$GATE_REPO" config user.name T
  mkdir -p "$GATE_REPO/src" "$GATE_REPO/other"
  printf 'one\n' > "$GATE_REPO/src/a.txt"
  printf 'elsewhere\n' > "$GATE_REPO/other/c.txt"
  printf 'ignored\n' > "$GATE_REPO/.gitignore"
  git -C "$GATE_REPO" add -A
  git -C "$GATE_REPO" commit -qm init
}

# Run a snippet with the prolog loaded, inside the throwaway repo. The prolog
# sets errexit, so a snippet must consume a helper's non-zero status itself.
# `GITLORE_GATE_FORCE` is cleared: this suite runs *inside* a gate, and an
# ambient value would reach every gate under test and make the skip cases
# silently unprovable. `GITLORE_GATE_DIR` likewise: an ambient one would move
# every sentinel the suites look for under the throwaway gitdir.
in_gate_repo() {
  (
    cd "$GATE_REPO" || return 1
    unset GITLORE_GATE_FORCE GITLORE_GATE_DIR
    # shellcheck source=/dev/null
    . "$PROLOG"
    eval "$1"
  )
}

# What a recipe does after its checks pass: `check-sentinel` is what names the
# sentinel and the input set, so `record-sentinel` is never reached without it.
gate_record() {
  in_gate_repo "check-sentinel g $1 || true; record-sentinel"
}
