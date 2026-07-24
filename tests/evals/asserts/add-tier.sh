#!/usr/bin/env bash
# Assertion: the /gitlore:add-tier round trip reached its end state.
#
# The whole chain in one flow: the agent writes the intent file and runs no git;
# the PostToolBatch hook mounts the tier out in the network-capable world; the
# agent activates it in the manifest; that edit retriggers composition, which
# splices the tier's pointer lines up into the always-loaded root index.
#
# See asserts/memory-commit.sh for the shared contract.
set -uo pipefail

fail() { printf '%s\n' "$1"; exit 1; }

TIER=acme
MEM="$EVAL_REPO/memory"
TIERPATH="$MEM/$TIER"

# 1. The intent file is one-shot: the hook consumes it whether it succeeded or
#    failed. Still present means the hook never ran at all.
[ ! -f "$EVAL_REPO/.claude/gitlore-add-tier" ] || \
  fail "intent file still present — the add-tier hook never consumed it"

# 2. Mounted. Guard on .git before any `git -C`: without a checkout, `git -C`
#    walks up and answers for the memory store instead.
[ -e "$TIERPATH/.git" ] || fail "tier '$TIER' is not checked out at $TIERPATH"

# 3. Registered in the memory store's OWN .gitmodules — discovery is by
#    enclosure, so this is what makes the tier findable at all.
[ -f "$MEM/.gitmodules" ] || fail "memory/.gitmodules does not exist; nothing was registered"
registered=$(git config --file "$MEM/.gitmodules" --get "submodule.$TIER.path") || registered=""
[ "$registered" = "$TIER" ] || \
  fail "memory/.gitmodules does not register '$TIER' at its own path (got '$registered')"

# 4. Detached at live — the tier branch model. A tier that came up on a named
#    branch would make the ff-only `fetch origin live:live` refuse forever.
if git -C "$TIERPATH" symbolic-ref -q HEAD >/dev/null; then
  fail "tier HEAD is on a branch ($(git -C "$TIERPATH" symbolic-ref --short HEAD)), not detached at live"
fi
tier_head=$(git -C "$TIERPATH" rev-parse HEAD)
if ! tier_live=$(git -C "$TIERPATH" rev-parse --verify -q refs/heads/live); then
  fail "tier has no local 'live' branch; propagation-in never happened"
fi
[ "$tier_head" = "$tier_live" ] || \
  fail "tier HEAD ($tier_head) is not at live ($tier_live)"

# 5. Activated. add-tier.sh appends the tier to the manifest as its own final
#    step — the intent already named this exact tier, so no separate agent edit
#    is needed. An unlisted tier would be mounted but dormant.
[ -f "$MEM/.gitlore-tiers" ] || fail "no activation manifest at memory/.gitlore-tiers"
grep -qx "$TIER" "$MEM/.gitlore-tiers" || \
  fail "manifest does not list '$TIER' — the tier is mounted but inactive. Manifest: $(tr '\n' ' ' < "$MEM/.gitlore-tiers")"

# 6. Composed. Activation retriggers the 3-ii compose pass, which splices the
#    tier's pointer lines into the root index with their tier prefix. This is
#    the payoff of the whole flow: the fact is now in always-loaded context.
grep -q "($TIER/reference_acme_staging_db.md)" "$MEM/MEMORY.md" || \
  fail "root index carries no '$TIER/'-prefixed line for the tier's seeded fact; composition did not run"

# 7. Nothing was committed inside the memory store. The mount is staged and
#    rides the next ordinary commit through the FR11 gate — the agent commits
#    nothing itself, and add-tier.sh is not a committer either.
baseline=$(cat "$EVAL_OUT_DIR/memory-baseline")
now=$(git -C "$MEM" rev-parse HEAD)
[ "$now" = "$baseline" ] || \
  fail "memory store advanced from $baseline to $now — something committed inside memory during add-tier, bypassing the FR11 gate"

# 8. …but the mount IS staged, which is what lets it ride that next commit.
git -C "$MEM" diff --cached --quiet -- .gitmodules "$TIER" && \
  fail "the mount is not staged in the memory index; it would be lost at the next commit"
exit 0
