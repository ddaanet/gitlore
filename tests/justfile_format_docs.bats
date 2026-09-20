#!/usr/bin/env bats
# The `format-docs` recipe: what it hands rumdl, what it spares under
# `plans/`, and how much of rumdl's own output it passes through.

load helpers/setup
load helpers/justfile-gates

@test "format-docs drives rumdl over docs/ and plans/, and refuses a version off the pin" {
  # The invocation path, with rumdl stubbed through the `rumdl` variable: what
  # the recipe hands it, and that a `.venv` behind `pyproject.toml` stops with
  # a message rather than wrapping the tree with whatever version is on PATH.
  # The args go to a file rather than stdout: the recipe filters its own
  # stdout down to a summary line, so asserting the invocation through that
  # channel would only prove what survived the filter.
  cat > "$STUB_DIR/rumdl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "rumdl $RUMDL_STUB_VERSION" ;;
  *) printf '%s\n' "$@" > "$RUMDL_STUB_ARGS"; printf 'Issues: none\n' ;;
esac
EOF
  chmod +x "$STUB_DIR/rumdl"
  pin=$(sed -n 's/.*"rumdl==\([0-9.]*\)".*/\1/p' "$PLUGIN_ROOT/pyproject.toml")
  [ -n "$pin" ]

  run bash -c "cd '$PLUGIN_ROOT' && RUMDL_STUB_VERSION='$pin' RUMDL_STUB_ARGS='$STUB_DIR/args' just rumdl='$STUB_DIR/rumdl' format-docs"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_DIR/args")" = $'fmt\n--no-cache\n--exclude\nplans/*/reports\ndocs\nplans' ]

  rm -f "$STUB_DIR/args"
  run bash -c "cd '$PLUGIN_ROOT' && RUMDL_STUB_VERSION=0.0.1 RUMDL_STUB_ARGS='$STUB_DIR/args' just rumdl='$STUB_DIR/rumdl' format-docs"
  [ "$status" -ne 0 ]
  [[ "$output" == *"pins $pin"* ]]
  [ ! -e "$STUB_DIR/args" ]
}

@test "the wrap set spares plans/*/reports/ and nothing else under plans/" {
  # A report is written once and read once, by an agent that has already left;
  # wrapping it rewrites a file nobody is going to read again, and the line cap
  # `check-docs-links.py` enforces covers `docs/` only, so an unwrapped report
  # escapes no check. The recipe's own argument list is replayed through the
  # real rumdl against a fixture tree: a stub would only prove the flag was
  # passed, not that the pattern matches what it is meant to.
  command -v rumdl > /dev/null || {
    echo "rumdl is not on PATH; run 'uv sync' and let direnv load .envrc" >&2
    return 1
  }
  cat > "$STUB_DIR/rumdl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "rumdl $RUMDL_STUB_VERSION" ;;
  *) printf '%s\n' "$@" > "$RUMDL_STUB_ARGS" ;;
esac
EOF
  chmod +x "$STUB_DIR/rumdl"
  pin=$(sed -n 's/.*"rumdl==\([0-9.]*\)".*/\1/p' "$PLUGIN_ROOT/pyproject.toml")
  run bash -c "cd '$PLUGIN_ROOT' && RUMDL_STUB_VERSION='$pin' RUMDL_STUB_ARGS='$STUB_DIR/args' just rumdl='$STUB_DIR/rumdl' format-docs"
  [ "$status" -eq 0 ]
  args=()
  while IFS= read -r arg || [ -n "$arg" ]; do
    args+=("$arg")
  done < "$STUB_DIR/args"

  # The repo's own config, so the fixture is wrapped by the rules the tree is.
  WRAP_TREE="$STUB_DIR/tree"
  mkdir -p "$WRAP_TREE/docs" "$WRAP_TREE/plans/job/reports"
  cp "$PLUGIN_ROOT/.rumdl.toml" "$WRAP_TREE/.rumdl.toml"
  long='One deliberately long line of prose, written to run past the eighty column boundary that MD013 reflow wraps at.'
  for f in docs/d.md plans/job/p.md plans/job/reports/r.md; do
    printf '# H\n\n%s\n' "$long" > "$WRAP_TREE/$f"
  done

  ( cd "$WRAP_TREE" && rumdl "${args[@]}" > /dev/null 2>&1 ) || true
  [ "$(wc -l < "$WRAP_TREE/docs/d.md")" -gt 3 ]
  [ "$(wc -l < "$WRAP_TREE/plans/job/p.md")" -gt 3 ]
  [ "$(wc -l < "$WRAP_TREE/plans/job/reports/r.md")" -eq 3 ]
}

@test "format-docs prints only rumdl's summary when it succeeds, all of it when it fails" {
  # The unwrappable-line residue reprints on every run and blocks nothing, so
  # a green `precommit` must not carry it; a run that actually failed must
  # carry every line, since that is the only place the reason appears.
  cat > "$STUB_DIR/rumdl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "rumdl $RUMDL_STUB_VERSION" ;;
  *)
    printf 'plans/a.md:1:81: [MD013] Line length 98 exceeds 80 characters\n'
    printf 'plans/b.md:2:81: [MD013] Line length 99 exceeds 80 characters\n'
    printf 'Issues: Found 2 issues in 2/3 files\n'
    exit "${RUMDL_STUB_RC:-0}"
    ;;
esac
EOF
  chmod +x "$STUB_DIR/rumdl"
  pin=$(sed -n 's/.*"rumdl==\([0-9.]*\)".*/\1/p' "$PLUGIN_ROOT/pyproject.toml")

  run bash -c "cd '$PLUGIN_ROOT' && RUMDL_STUB_VERSION='$pin' just rumdl='$STUB_DIR/rumdl' format-docs"
  [ "$status" -eq 0 ]
  [ "$output" = "Issues: Found 2 issues in 2/3 files" ]
  [[ "$output" != *"MD013"* ]]

  run bash -c "cd '$PLUGIN_ROOT' && RUMDL_STUB_VERSION='$pin' RUMDL_STUB_RC=2 just rumdl='$STUB_DIR/rumdl' format-docs"
  [ "$status" -eq 2 ]
  [[ "$output" == *"plans/a.md:1:81: [MD013]"* ]]
  [[ "$output" == *"plans/b.md:2:81: [MD013]"* ]]
}
