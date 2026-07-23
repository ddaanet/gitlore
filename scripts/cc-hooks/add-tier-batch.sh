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
# The intent file IS the signal, so the batch payload is unused.
#
# One-shot, like the recall request and unlike the commit trigger: an add-tier
# failure is a bad url or a taken name, not a transient lock, so retrying it on
# every subsequent batch would just re-report the same error. The agent fixes
# the intent and writes it again.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

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
  emit "$out" "$out

The tier is mounted but INACTIVE — nothing composes or advertises until it is listed. Your next step is the deliberate one: add its name as a line in $mempath/.gitlore-tiers (file order is precedence, top wins), which retriggers composition. Do not run any git yourself; the mount is already staged in $mempath/.gitmodules and rides the next parent commit."
else
  emit "$out" "gitlore add-tier failed and mounted nothing. The intent file was consumed. Fix the cause, then write $intent again with corrected key=value lines. Problem:
$out"
fi
exit 0
