#!/usr/bin/env bash
# Assertion: the /gitlore:add-tier round trip reached its end state.
#
# The whole chain in one flow: the agent writes the intent file and runs no git;
# the PostToolBatch hook mounts the tier out in the network-capable world and
# activates it in the manifest; that edit retriggers composition, which
# splices the tier's pointer lines up into the always-loaded root index.
#
# The flow ends in a commit: the agent reports the staged mount, drafts a
# `== memory ==` summary through the gitlore:commit skill and stops for approval;
# on approval (turn 2) it commits the mount with gitlore-commit. The assertion
# grades that hand-off — memory unmoved before approval, the skill ahead of
# gitlore-commit, the mount in the commit, live fast-forwarded and the parent
# pointer staged.
#
# See asserts/memory-commit.sh for the shared contract.
set -uo pipefail

fail() { printf '%s\n' "$1"; exit 1; }

# shellcheck disable=SC1091  # dynamic path resolved at runtime
source "$LIB_DIR/finish-commit.sh"

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

# 7. The mount was committed through the approved-summary path. Memory did not
#    move before the user approved, and the commit that followed went through
#    the gitlore:commit skill.
baseline=""
[ -f "$EVAL_OUT_DIR/memory-baseline" ] && baseline=$(cat "$EVAL_OUT_DIR/memory-baseline")
[ -n "$baseline" ] || fail "no memory baseline captured; the harness did not record where the store started"

check_no_commit_before_approval "$baseline"

path_taken=""   # set by settle_commit_path
settle_commit_path "$MEM" "$baseline"
check_commit_trace

# 8. The commits from the baseline carry the whole mount: the registration, the
#    activation and the tier's gitlink.
committed=$(git -C "$MEM" diff --name-only "$baseline" HEAD)
for path in .gitmodules .gitlore-tiers "$TIER"; do
  printf '%s\n' "$committed" | grep -qxF "$path" || \
    fail "the mount commit does not include '$path' ($path_taken; committed: ${committed//$'\n'/ })"
done

# 9. Nothing of the mount is left staged but uncommitted.
leftover=$(git -C "$MEM" diff --cached --name-only -- .gitmodules .gitlore-tiers "$TIER")
[ -z "$leftover" ] || \
  fail "the mount is still staged but uncommitted in memory: ${leftover//$'\n'/ }"

# 10. live fast-forwarded to the commit.
head=$(git -C "$MEM" rev-parse HEAD)
live=$(git -C "$MEM" rev-parse live)
[ "$head" = "$live" ] || fail "live not ff-pushed (HEAD=$head live=$live)"

# 11. The parent records the new memory pointer.
check_memory_pointer_staged
exit 0
