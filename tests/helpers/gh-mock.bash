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

# `gh repo view <url> --json visibility -q .visibility` → GH_MOCK_VISIBILITY.
if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ] && \
   printf '%s\n' "$@" | grep -q 'visibility' && [ -n "${GH_MOCK_VISIBILITY:-}" ]; then
  printf '%s\n' "$GH_MOCK_VISIBILITY"
  exit 0
fi

# `gh repo view <name> --json sshUrl -q .sshUrl` returns the configured remote URL
# unless a per-call override is set. Lets tests script the URL the install flow
# wires into the submodule.
if [ -z "$stdout_val" ] && [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ] && \
   printf '%s\n' "$@" | grep -q 'sshUrl' && [ -n "${GH_MOCK_REMOTE_URL:-}" ]; then
  stdout_val="$GH_MOCK_REMOTE_URL"
fi

[ -n "$stdout_val" ] && printf '%s\n' "$stdout_val"
[ -n "$stderr_val" ] && printf '%s\n' "$stderr_val" >&2
exit "$exit_code"
EOF
  chmod +x "$bindir/gh"
  export PATH="$bindir:$PATH"
}
