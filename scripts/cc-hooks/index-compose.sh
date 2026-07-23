#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

# PostToolBatch, like the index→frontmatter sync: it fires once per turn with
# every call in .tool_calls[], so a turn holding several index edits composes —
# and reports — once instead of per edit.
payload=$(cat)
files=$(jq -r '
  .tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit")
  | .tool_input.file_path // empty' <<<"$payload")
[ -n "$files" ] || exit 0

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"
manifest="$mempath/.gitlore-tiers"
[ -e "$index" ] || exit 0

# Did this batch write the root index or the activation manifest? Identity via
# -ef, as in the sync hooks: the payload carries absolute paths and $mempath is
# relative to the repo root.
touched=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -e "$f" ] || continue
  if [ "$f" -ef "$index" ]; then touched=1; break; fi
  if [ -e "$manifest" ] && [ "$f" -ef "$manifest" ]; then touched=1; break; fi
done <<<"$files"
[ -n "$touched" ] || exit 0

sysmsg=""
ctx=""
compose_rc=0
result=$(gitlore_compose "$mempath") || compose_rc=$?
if [ "$compose_rc" -eq 0 ]; then
  if [ -n "$result" ]; then
    n=$(printf '%s\n' "$result" | grep -c '^composed ')
    if [ "$n" -eq 1 ]; then unit="index"; else unit="indexes"; fi
    sysmsg="gitlore: recomposed tier pointers ($n $unit)"
    ctx="The gitlore tier composition rewrote these indexes to place each active tier's pointer block ahead of the project's own lines, and mirrored root-authored tier lines down into their carrier. This is expected and complete — do not re-read or re-edit them to verify. Composition moves lines only; it never changes a line's text.
$result"
  fi

  # The fifth validation reports rather than refuses, so it runs on the composed
  # store and rides the same message whether or not anything was written.
  dangling=$(gitlore_compose_dangling "$mempath")
  if [ -n "$dangling" ]; then
    d=$(printf '%s\n' "$dangling" | grep -c .)
    if [ "$d" -eq 1 ]; then dunit="pointer"; else dunit="pointers"; fi
    sysmsg="${sysmsg:+$sysmsg
}gitlore: $d dangling index $dunit — a line names a file that is not there"
    ctx="${ctx:+$ctx

}These memory index lines point at files that do not exist. Nothing was rewritten or deleted: the index is authoritative over what memory contains, so a line outliving its file is a stale pointer to fix, not a reason to refuse the pass. Either restore the file or remove the line — removing it deletes nothing.
$dangling"
  fi
elif [ "$compose_rc" -eq 2 ]; then
  # A write failed partway, so the fail-safe promise does NOT hold here: some
  # indexes are composed and at least one is not. Say so — the recovery is the
  # same retrigger, but the store is not in the state a refusal leaves it in.
  sysmsg="gitlore: tier composition could not write an index — the memory indexes are only partly composed:
$result"
  ctx="gitlore tier composition failed while writing. Unlike a refusal, this leaves the memory indexes PARTLY composed: everything listed as composed was written, and the file named after them was not. Investigate that path (permissions, disk space, a read-only worktree), then edit MEMORY.md or memory/.gitlore-tiers again to retrigger the pass:
$result"
else
  # Fail-safe: nothing was written. Never exit non-zero — stdout JSON parses on
  # exit 0 only, so a non-zero exit would DISCARD this message and make the
  # failure less visible, not more (D14).
  sysmsg="gitlore: tier composition refused — the memory indexes were left untouched:
$result"
  ctx="gitlore tier composition refused and wrote nothing. Fix the store by hand, then edit MEMORY.md or memory/.gitlore-tiers again to retrigger it. Problems:
$result"
fi

if [ -n "$sysmsg" ]; then
  jq -n --arg s "$sysmsg" --arg c "$ctx" \
    '{systemMessage: $s, suppressOutput: true,
      hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}'
fi
exit 0
