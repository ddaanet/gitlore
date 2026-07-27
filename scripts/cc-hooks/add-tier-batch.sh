#!/usr/bin/env bash
set -euo pipefail

# PostToolBatch: mount a memory tier WITHOUT the agent ever running git.
#
# The agent writes one ordinary file — the intent (gitlore-add-tier) — and this
# hook runs add-tier.sh on its behalf. Two separate reasons the agent cannot do
# this itself: the auto-mode classifier reads a submodule mutation as
# self-modification, and mounting CLONES while the command sandbox has no
# network. A hook runs outside both.
#
# add-tier.sh activates the tier as its own final step (appends it to
# memory/.gitlore-tiers) — the intent already named this exact tier, so there is
# no half-formed-tier ambiguity left for a second, separate deliberate edit to
# guard against. That write happens after index-compose.sh's baseline was taken
# and cannot be attributed to a tool call, so this hook calls the shared
# compose-and-report helper directly and folds its result into the one JSON
# response a hook may emit.
#
# The intent file IS the signal, so the batch payload is unused.
#
# One-shot, like the recall request and unlike the commit trigger: an add-tier
# failure is a bad url or a taken name, not a transient lock, so retrying it on
# every subsequent batch would just re-report the same error. The agent fixes
# the intent and writes it again.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# gitlore_compose_and_report, to recompose after add-tier.sh activates the tier.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
# gitlore_get_frontmatter_description / gitlore_active_tier_scopes dependency,
# needed by gitlore_compose_and_report's triage-nudge block.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

cat >/dev/null || true   # drain stdin; the intent file, not the payload, drives us

emit() {   # $1 = systemMessage, $2 = additionalContext
  jq -n --arg s "$1" --arg c "$2" \
    '{systemMessage: $s, suppressOutput: true,
      hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}'
}

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
[ -e "$mempath/.git" ] || exit 0          # session-less worktree: nothing to mount into

intent=$(gitlore_add_tier_file "$mempath")
[ -f "$intent" ] || exit 0                # no request this batch → nothing to do

rc=0
out=$(bash "$PLUGIN_ROOT/scripts/add-tier.sh" 2>&1) || rc=$?
rm -f "$intent"

if [ "$rc" -eq 0 ]; then
  # add-tier.sh already appended $name to the manifest — the active-tier set
  # changed, so recompose and let the triage nudge fire, same as a manual edit.
  gitlore_compose_and_report "$mempath" 1
  # This batch's compose is done. Drop index-compose.sh's baseline so it does not
  # re-report the same manifest change: it keys on a pre-batch stamp, and the
  # activation write above moved it. Best-effort tidying of a duplicate message —
  # a second pass would be idempotent, not wrong.
  rm -f "$(gitlore_compose_stamp_file "$mempath")"
  sysmsg="$out"
  ctx="$out

Do not run any git yourself; the mount and activation are already staged in $mempath (the submodule in .gitmodules, the tier's name in .gitlore-tiers) and ride the next parent commit."
  if [ -n "$GITLORE_COMPOSE_SYSMSG" ]; then
    sysmsg="$sysmsg
$GITLORE_COMPOSE_SYSMSG"
    ctx="$ctx

$GITLORE_COMPOSE_CTX"
  fi
  emit "$sysmsg" "$ctx"
else
  emit "$out" "gitlore add-tier failed and mounted nothing. The intent file was consumed. Fix the cause, then write $intent again with corrected key=value lines. Problem:
$out"
fi
exit 0
