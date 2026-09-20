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
# silently unprovable.
in_gate_repo() {
  (
    cd "$GATE_REPO" || return 1
    unset GITLORE_GATE_FORCE
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
