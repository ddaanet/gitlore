#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
# gitlore_active_tier_scopes (util.sh) calls gitlore_get_frontmatter_description,
# defined here — needed for the post-mount triage nudge below.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

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

# Did this batch write the root index or the activation manifest? Tracked
# separately: the triage nudge below fires on a manifest change specifically
# (the active-tier set may have changed), not on every memory-writing recompose.
# Identity via -ef, as in the sync hooks: the payload carries absolute paths
# and $mempath is relative to the repo root.
index_touched=""
manifest_touched=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -e "$f" ] || continue
  if [ "$f" -ef "$index" ]; then index_touched=1; fi
  if [ -e "$manifest" ] && [ "$f" -ef "$manifest" ]; then manifest_touched=1; fi
done <<<"$files"
[ -n "$index_touched$manifest_touched" ] || exit 0

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

  # Post-mount triage nudge (D17 triage-automation design): the active-tier
  # set may just have changed, so gate on the manifest specifically, not any
  # compose. Scopes come from the live frontmatter of each active tier — never
  # a fixed dichotomy — so this reads correctly whether one tier is active or
  # several, and whatever each one's own scope says.
  if [ -n "$manifest_touched" ]; then
    scopes=$(gitlore_active_tier_scopes "$mempath")
    if [ -n "$scopes" ]; then
      n=$(printf '%s\n' "$scopes" | grep -c .)
      if [ "$n" -eq 1 ]; then tunit="tier"; else tunit="tiers"; fi
      # Emit a systemMessage too, not just additionalContext: without one, a
      # manifest touch that recomposed nothing (no sysmsg from above) would
      # skip the final emit gate below and silently drop this directive.
      sysmsg="${sysmsg:+$sysmsg
}gitlore: active-tier set changed ($n $tunit) — triage local memory against their scopes"
      scope_lines=$(printf '%s\n' "$scopes" | sed 's/^/  - /')
      ctx="${ctx:+$ctx

}gitlore: the active-tier set just changed. For each fact in your LOCAL memory (a bare-path \`- [Title](file.md)\` line in $index), judge which active tier's scope best covers it — using each tier's OWN scope below, not a fixed rule:
$scope_lines
Route the best-fit ones up: \`mv\` the file into that tier's directory, and reprefix its root index line to \`<tier>/<file>.md\`. A fact no active tier's scope covers stays local. Do not move a fact already in a tier."
    fi
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
