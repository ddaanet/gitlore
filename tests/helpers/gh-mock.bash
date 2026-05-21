#!/usr/bin/env bash
# Per-test gh mock. Call install_gh_mock from setup(). Scripted behavior:
#   GH_MOCK_EXIT, GH_MOCK_STDOUT, GH_MOCK_STDERR, GH_MOCK_LOG
# Per-subcommand overrides: GH_MOCK_EXIT_REPO_CREATE, GH_MOCK_STDOUT_API_USER, etc.
# (uppercase, _-joined first two args.)

install_gh_mock() {
  local bindir="$TMP_REPO/.gh-mock-bin"
  mkdir -p "$bindir"
  cat > "$bindir/gh" <<'EOF'
#!/usr/bin/env bash
if [ -n "${GH_MOCK_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$GH_MOCK_LOG"
fi

sub=$(printf '%s_%s' "${1:-}" "${2:-}" | tr 'a-z-' 'A-Z_')
override_exit_var="GH_MOCK_EXIT_${sub}"
override_stdout_var="GH_MOCK_STDOUT_${sub}"
override_stderr_var="GH_MOCK_STDERR_${sub}"

exit_code="${!override_exit_var:-${GH_MOCK_EXIT:-0}}"
stdout_val="${!override_stdout_var:-${GH_MOCK_STDOUT:-}}"
stderr_val="${!override_stderr_var:-${GH_MOCK_STDERR:-}}"

if [ -z "$stdout_val" ] && [ "${1:-}" = "--version" ]; then
  stdout_val="gh version mock 0.0.0 (mock build)"
fi

# Simulate `gh repo create ... --source=. --push` side effects on success.
if [ "$exit_code" = "0" ] && [ "${1:-}" = "repo" ] && [ "${2:-}" = "create" ]; then
  has_source_dot=0
  has_push=0
  for arg in "$@"; do
    case "$arg" in
      --source=.) has_source_dot=1 ;;
      --push)     has_push=1 ;;
    esac
  done
  if [ "$has_source_dot" = "1" ] && [ "$has_push" = "1" ] && [ -n "${GH_MOCK_REMOTE_URL:-}" ]; then
    if ! git remote get-url origin >/dev/null 2>&1; then
      git remote add origin "$GH_MOCK_REMOTE_URL"
    fi
    git push -q origin HEAD 2>/dev/null || true
  fi
fi

[ -n "$stdout_val" ] && printf '%s\n' "$stdout_val"
[ -n "$stderr_val" ] && printf '%s\n' "$stderr_val" >&2
exit "$exit_code"
EOF
  chmod +x "$bindir/gh"
  export PATH="$bindir:$PATH"
}
