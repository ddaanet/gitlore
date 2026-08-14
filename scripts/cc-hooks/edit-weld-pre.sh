#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/edit-weld.sh"

# D23. Record what a weldable `Edit` is asking for, so the post hook can tell
# whether the tool delivered it. Computing the intended result up front is what
# turns "something risky happened" into an observation and a repair: a marker
# alone leaves the corruption in place and leaves the agent to infer, from a
# downstream check finding nothing, that the defect is gone.
payload=$(cat)

# One jq pass for everything that does not need the file, so a call that cannot
# weld costs a single process and no read. The argument-shape test rides in the
# last field: `old_string` is emitted only for a call that could weld — empty
# `new_string`, no `replace_all` — so an empty field means disarmed.
#
# NUL-delimited, because `old_string` routinely ends in a newline. That byte is
# what the whole guard is about, and both `$(...)` and a newline-delimited read
# would eat it.
{ IFS= read -r -d '' tool
  IFS= read -r -d '' session
  IFS= read -r -d '' file
  IFS= read -r -d '' old
} < <(printf '%s' "$payload" | jq -j '
    [ (.tool_name // ""),
      (.session_id // ""),
      (.tool_input.file_path // ""),
      (if (.tool_input.new_string == "") and (.tool_input.replace_all != true)
       then (.tool_input.old_string // "") else "" end)
    ] | map(. + "\u0000") | add') || exit 0

[ "$tool" = Edit ] || exit 0
[ -n "$old" ] || exit 0
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

# Narrower than the argument shape: the match must also be followed by a
# newline, or there is no second separator to lose and `Edit` is correct.
plan=$(gitlore_weld_plan "$file" "$old") || exit 0

dir=$(gitlore_weld_state_dir)
state=$(gitlore_weld_state_file "$session" "$file")
if ! err=$( { mkdir -p "$dir" && printf '%s\n' "$plan" > "$state"; } 2>&1 ); then
  # Never exit 2 (would block the Edit) and never exit 1 (stdout JSON is only
  # parsed on exit 0 — D14). Losing the expectation costs the repair silently,
  # and the compose check that would otherwise catch the damage only covers
  # index files, so this is reported rather than logged.
  printf 'gitlore: failed to record the pre-edit expectation (%s): %s\n' "$state" "$err" >&2
  jq -n --arg f "$file" --arg err "$err" \
    '{systemMessage: ("gitlore: could not record the pre-edit expectation for " + $f + " (" + $err + "); a welded Edit will not be repaired this time")}'
  exit 0
fi

# Sweep expectations left by sessions that ended between the two hooks. Only
# reached on the armed path, which is rare enough that the walk costs nothing.
find "$dir" -maxdepth 1 -type f -mtime +1 -delete || :
exit 0
