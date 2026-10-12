#!/usr/bin/env bash
# Shared by tests/hook_guard.bats and tests/hook_guard_fallback.bats: a fixture
# hook written into the temp repo and run as `bash script` the way CC runs a
# hook, plus the assertions on the report a dying hook emits. Load after
# helpers/setup. Needs bats' $status/$output/$stderr, set by `run`.
# shellcheck disable=SC2154,SC2016  # the fixture lines are literal; $status etc. come from `run`

hook_guard_setup() {
  setup_tmp_repo
  make_parent_with_memory
  FIX="$TMP_REPO/fixture-hook.sh"
  GITDIR=$(git -C memory rev-parse --absolute-git-dir)
}

hook_guard_teardown() {
  # The unwritable tests leave read-only directories that rm -rf cannot enter.
  [ -z "${TMP_REPO:-}" ] || chmod -R u+w "$TMP_REPO"
  teardown_tmp_repo
}

# A hook in miniature: strict mode, the shared library, the project root, the
# memory path, then the guard. $1 runs before the guard call, $2 after it.
write_fixture() {
  cat > "$FIX" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
# Shaped like scripts/cc-hooks/index-sync-post.sh: the library, the launch
# repo, the memory path, then the guard, then whatever can die.
source "$CLAUDE_PLUGIN_ROOT/scripts/lib/util.sh"
gitlore_cd_project_root || exit 0
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
SCRIPT
  {
    printf '%s\n' "$1"
    printf '%s\n' 'gitlore_batch_hook_guard "fixture-hook" "$mempath" "CONSEQUENCE-MARK the fixture did not finish."'
    printf '%s\n' "$2"
  } >> "$FIX"
}

# A command that dies with status $1 after writing "boom-from-child" to stderr.
# Neither the marker nor "exit <status>" occurs in the command's own text, so a
# report that carries only $BASH_COMMAND cannot satisfy the stderr or status
# assertions: the marker is built from $0 and the status passed as $1.
death_cmd() {
  printf '%s' "sh -c 'echo \"boom-\$0\" >&2; exit \"\$1\"' from-child $1"
}

# The 1-based line in the fixture of the last line containing $1 literally.
fixture_line() {
  grep -nF -- "$1" "$FIX" | tail -1 | cut -d: -f1
}

# Run the fixture as CC would. Extra arguments are env assignments.
run_fixture() {
  run --separate-stderr env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    CLAUDE_PROJECT_DIR="$TMP_REPO" "$@" bash "$FIX"
}

gitdir_listing() {
  find "$GITDIR" | sort
}

# Exactly one JSON object on stdout, for the PostToolBatch event.
assert_one_object() {
  [ "$(jq -s 'length' <<<"$output")" = 1 ]
  jq -e 'type == "object"' <<<"$output" >/dev/null
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "PostToolBatch" ]
}

sys_msg() { jq -r '.systemMessage' <<<"$output"; }
ctx_msg() { jq -r '.hookSpecificOutput.additionalContext' <<<"$output"; }

# $1 = message; $2 = numeric status. "status 5", "exit 5" and "code=5" all pass.
msg_has_status() {
  local re="(status|exit|code)[ :=]*$2([^0-9]|\$)"
  [[ "$1" =~ $re ]]
}

# $1 = message; $2 = line number.
msg_has_line() {
  local re="line[ :=]*$2([^0-9]|\$)"
  [[ "$1" =~ $re ]]
}

# $1 = message; $2/$3 = lowest and highest acceptable reported line.
msg_line_in_range() {
  local re='line[ :=]*([0-9]+)'
  [[ "$1" =~ $re ]] || return 1
  [ "${BASH_REMATCH[1]}" -ge "$2" ] && [ "${BASH_REMATCH[1]}" -le "$3" ]
}

# The report every death carries, on both channels: hook name, status and the
# dying command's stderr. $3 is the command's source text, checked first to
# share neither with the report's wanted status nor its stderr marker, so the
# report cannot satisfy the assertions with $BASH_COMMAND alone.
assert_death_report() {
  local want_status="$1" want_text="$2" cmd="$3" channel msg
  # `!` alone asserts nothing under bats, so the test is spelled out.
  if msg_has_status "$cmd" "$want_status"; then return 1; fi
  [[ "$cmd" != *"$want_text"* ]]
  [ "$status" -eq 0 ]
  assert_one_object
  for channel in sys_msg ctx_msg; do
    msg=$("$channel")
    [[ "$msg" == *"fixture-hook"* ]]
    msg_has_status "$msg" "$want_status"
    [[ "$msg" == *"$want_text"* ]]
  done
}

# What a real hook's death looks like from outside (D60). $1 = the hook's name
# (its script's basename without `.sh`); $2 = the status it died with; the rest
# = the stable tokens of the hook's consequence sentence. Exit 0, one object,
# both channels naming the hook and the status, every token on additionalContext
# and none on systemMessage, and no capture file left in the memory git dir.
assert_hook_died() {
  local name="$1" want="$2" token channel
  shift 2
  [ "$status" -eq 0 ]
  assert_one_object
  for channel in sys_msg ctx_msg; do
    [[ "$("$channel")" == *"hook $name died with status $want"* ]]
  done
  for token in "$@"; do
    [[ "$(ctx_msg)" == *"$token"* ]]
    if [[ "$(sys_msg)" == *"$token"* ]]; then return 1; fi
  done
  [ -z "$(find "$(git -C memory rev-parse --absolute-git-dir)" -maxdepth 1 -name 'gitlore-hook-*')" ]
}
