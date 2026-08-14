#!/usr/bin/env bats
# The PreToolUse/PostToolUse pair that contains the `Edit` weld defect (D23).
#
# The pair is scoped to every `Edit`, not to index files: the shape test is
# cheap, the defect is not index-specific, and narrowing it would leave other
# files silently welded while starving the retirement signal of samples. So
# nothing here sets up a gitlore store — a bare directory is the fixture.

bats_require_minimum_version 1.5.0

load helpers/setup

PRE="$PLUGIN_ROOT/scripts/cc-hooks/edit-weld-pre.sh"
POST="$PLUGIN_ROOT/scripts/cc-hooks/edit-weld-post.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export TMPDIR="$TMP_REPO/tmp"
  mkdir -p "$TMPDIR"
  printf 'A\nX\nB\n' > f
}
teardown() { teardown_tmp_repo; }

# $1 = old_string, $2 = new_string, $3 = target (default f), $4 = replace_all.
payload() {
  jq -nc --arg o "$1" --arg n "$2" --arg f "${3:-$TMP_REPO/f}" \
         --argjson r "${4:-false}" \
    '{tool_name:"Edit", session_id:"s1",
      tool_input:{file_path:$f, old_string:$o, new_string:$n, replace_all:$r}}'
}

pre()  { printf '%s' "$1" | bash "$PRE"; }
post() { printf '%s' "$1" | bash "$POST"; }

# The one expectation file the pre hook may have written, if any.
states() {
  local dir="$TMPDIR/gitlore-edit-weld"
  [ -d "$dir" ] || { printf '0\n'; return 0; }
  find "$dir" -maxdepth 1 -type f -name '[0-9]*' | wc -l
}

ctx() { jq -r '.hookSpecificOutput.additionalContext // ""'; }
msg() { jq -r '.systemMessage // ""'; }

# --- arming ------------------------------------------------------------------

@test "pre arms on a weldable deletion" {
  run pre "$(payload $'\nX' '')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]          # arming is silent; only the verdict speaks
  [ "$(states)" = 1 ]
}

@test "pre stays disarmed when new_string is not empty" {
  run pre "$(payload $'\nX' $'\nY')"
  [ "$status" -eq 0 ]
  [ "$(states)" = 0 ]
}

@test "pre stays disarmed when old_string does not begin with a newline" {
  run pre "$(payload 'X' '')"
  [ "$status" -eq 0 ]
  [ "$(states)" = 0 ]
}

@test "pre stays disarmed when the match ends the file" {
  # Nothing follows the match, so there is no second separator to lose.
  run pre "$(payload $'\nB\n' '')"
  [ "$status" -eq 0 ]
  [ "$(states)" = 0 ]
}

@test "pre stays disarmed on replace_all" {
  # Never once co-occurred with the risky shape across the local corpus, and
  # multi-match deletion is a different computation. Bounded deliberately.
  run pre "$(payload $'\nX' '' "$TMP_REPO/f" true)"
  [ "$status" -eq 0 ]
  [ "$(states)" = 0 ]
}

@test "pre stays disarmed for a tool that is not Edit" {
  p=$(payload $'\nX' '' | jq -c '.tool_name = "Write"')
  run pre "$p"
  [ "$status" -eq 0 ]
  [ "$(states)" = 0 ]
}

@test "pre stays disarmed when the target does not exist" {
  run pre "$(payload $'\nX' '' "$TMP_REPO/absent.md")"
  [ "$status" -eq 0 ]
  [ "$(states)" = 0 ]
}

@test "pre keeps old_string's trailing newline" {
  # A newline-delimited read or a `$(...)` capture eats exactly the byte the
  # guard exists for, and the plan would then key on a shorter match.
  printf 'A\nX\n\nB\n' > f
  run pre "$(payload $'\nX\n' '')"
  [ "$status" -eq 0 ]
  [ "$(states)" = 1 ]
  state=$(find "$TMPDIR/gitlore-edit-weld" -type f -name '[0-9]*')
  jq -j '.weld' "$state" > got
  printf 'AB\n' > want
  cmp got want
}

# --- verdicts ----------------------------------------------------------------

# Arm, then leave the target holding $1, then report what post did.
after() {
  pre "$(payload $'\nX' '')"
  printf '%s' "$1" > f
  post "$(payload $'\nX' '')"
}

@test "post repairs a welded file and says so on both channels" {
  run after 'AB
'
  [ "$status" -eq 0 ]
  printf 'A\nB\n' > want
  cmp f want
  [[ "$(printf '%s' "$output" | msg)" == *"repaired a welded Edit"* ]]
  [[ "$(printf '%s' "$output" | ctx)" == *"$TMP_REPO/f"* ]]
}

@test "post reports a clean result as the retirement signal, and writes nothing" {
  run after 'A
B
'
  [ "$status" -eq 0 ]
  printf 'A\nB\n' > want
  cmp f want
  [[ "$(printf '%s' "$output" | msg)" == *"did not fire"* ]]
  [[ "$(printf '%s' "$output" | msg)" == *retire* ]]
  # User-only: the agent has nothing to do, and retiring is not its call.
  [ -z "$(printf '%s' "$output" | ctx)" ]
}

@test "post stays silent when the edit did not land" {
  run after 'A
X
B
'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf 'A\nX\nB\n' > want
  cmp f want                      # and above all, writes nothing
}

@test "post reports an unrecognised result without writing" {
  run after 'something else'
  [ "$status" -eq 0 ]
  [[ "$(printf '%s' "$output" | msg)" == *"out of date"* ]]
  printf 'something else' > want
  cmp f want
}

@test "post consumes the expectation whatever the verdict" {
  # A survivor would be compared against the next, unrelated edit of the file.
  after 'A
X
B
' >/dev/null
  [ "$(states)" = 0 ]
}

@test "post is a no-op when nothing armed" {
  run post "$(payload $'\nX' '')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "post ignores an expectation belonging to another session" {
  pre "$(payload $'\nX' '')"
  printf 'AB\n' > f
  p=$(payload $'\nX' '' | jq -c '.session_id = "s2"')
  run post "$p"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  printf 'AB\n' > want
  cmp f want
}

# --- the invocation path -----------------------------------------------------

@test "distribution: both hooks are wired on Edit and ship executable" {
  run jq -r '.hooks.PreToolUse[] | select(.matcher=="Edit") | .hooks[].command' \
      "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *edit-weld-pre.sh ]]
  run jq -r '.hooks.PostToolUse[] | select(.matcher=="Edit") | .hooks[].command' \
      "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *edit-weld-post.sh ]]
  # Recorded mode, not the local filesystem mode: a marketplace clone
  # reproduces git's mode, and a local chmod would mask a 100644.
  for s in edit-weld-pre edit-weld-post; do
    [ -x "$PLUGIN_ROOT/scripts/cc-hooks/$s.sh" ]
    run git -C "$PLUGIN_ROOT" ls-files -s "scripts/cc-hooks/$s.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == 100755* ]]
  done
}
