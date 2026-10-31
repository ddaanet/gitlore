#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/edit-weld.sh"

# D23. Compare the target against the expectation the pre hook recorded, and act
# on which of the four possible answers came back. `PostToolUse` cannot block,
# but it can write, and on the repair path the write is the whole point: the
# join is undone at the edit site, before composition, the index→frontmatter
# sync, or any pattern check sees it.
payload=$(cat)

{ IFS= read -r -d '' tool
  IFS= read -r -d '' session
  IFS= read -r -d '' file
} < <(printf '%s' "$payload" | jq -j '
    [ (.tool_name // ""), (.session_id // ""), (.tool_input.file_path // "") ]
    | map(. + "\u0000") | add') || exit 0

[ "$tool" = Edit ] || exit 0
[ -n "$file" ] || exit 0

state=$(gitlore_weld_state_file "$session" "$file")
[ -f "$state" ] || exit 0
# Consumed whatever the verdict. An expectation left behind would be compared
# against some later, unrelated edit of the same file in the same session.
trap 'rm -f "$state"' EXIT
[ -f "$file" ] || exit 0

# suppressOutput hides the raw stdout from the transcript; systemMessage is the
# user's channel, additionalContext the model's.
emit() {   # $1 = systemMessage, $2 = additionalContext (omit for user-only)
  if [ $# -gt 1 ]; then
    jq -n --arg s "$1" --arg c "$2" \
      '{systemMessage: $s, suppressOutput: true,
        hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
  else
    jq -n --arg s "$1" '{systemMessage: $s, suppressOutput: true}'
  fi
}

case "$(gitlore_weld_verdict "$state" "$file")" in
  repair)
    if err=$(gitlore_weld_repair "$state" "$file" 2>&1); then
      emit \
        "gitlore: repaired a welded Edit in $file — the deletion took the newline on both sides of the match and joined its neighbours onto one line." \
        "gitlore repaired $file immediately after that Edit. Claude Code's Edit consumed the separator on both sides of a leading-newline deletion and welded the neighbouring lines into one; the file on disk now holds exactly what the edit asked for, so your own model of it is the correct one. Read the file again before editing that region, since the bytes on disk changed after the tool reported."
    else
      printf 'gitlore: failed to repair the welded Edit (%s): %s\n' "$file" "$err" >&2
      emit \
        "gitlore: $file came back from Edit with its neighbouring lines welded, and the repair failed ($err). The join is still there." \
        "The Edit on $file welded two lines into one — Claude Code's Edit takes the newline on both sides of a leading-newline deletion — and gitlore could not repair it ($err). Read the file and restore the separator by hand."
    fi
    ;;
  clean)
    # The retirement signal, and the reason the pair computes an expectation
    # rather than dropping a marker: a clean result on a shape that CAN weld is
    # an observation, not the absence of one. User-only by design — the agent
    # has nothing to do with it, and the decision to retire is not its call.
    emit "gitlore: Edit deleted a leading-newline match in $file without welding its neighbours — the defect the D23 guard contains did not fire. Once that holds across a run of these, the guard and the welded-bullet index rule can both retire."
    ;;
  unchanged)
    # The edit did not land — refused, denied, or matching nothing. Writing the
    # expectation here would apply a deletion the tool declined to make.
    :
    ;;
  *)
    emit \
      "gitlore: after an Edit on $file the result matched neither the intended text nor the known weld — the D23 guard's model of Edit is out of date. Nothing was written." \
      "gitlore expected that Edit on $file to produce either the text you asked for or a known welded variant of it, and got neither. Nothing was written, so the file holds whatever Edit left. Read it before relying on its contents."
    ;;
esac
exit 0
