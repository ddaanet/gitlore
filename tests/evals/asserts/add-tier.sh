#!/usr/bin/env bash
# Assertion: the /gitlore:add-tier flow reached its end state.
#
# One turn: the agent runs `gitlore-add-tier` with the intent on stdin, and the
# script mounts the tier, activates it in the manifest, recomposes the root
# index, and — on a clean store — commits the mount itself under its canned
# message (D71). The assertion grades that commit: one commit past the baseline,
# the canned subject, the mount's paths and nothing else, live fast-forwarded,
# the parent's memory gitlink staged. No gitlore:commit skill call is needed.
#
# See asserts/memory-commit.sh for the shared contract.
set -uo pipefail

fail() { printf '%s\n' "$1"; exit 1; }

# shellcheck disable=SC1091  # dynamic path resolved at runtime
source "$LIB_DIR/finish-commit.sh"

TIER=acme
MEM="$EVAL_REPO/memory"
TIERPATH="$MEM/$TIER"

# 1. Mounted. Guard on .git before any `git -C`: without a checkout, `git -C`
#    walks up and answers for the memory store instead.
[ -e "$TIERPATH/.git" ] || fail "tier '$TIER' is not checked out at $TIERPATH"

# 2. Registered in the memory store's OWN .gitmodules — discovery is by
#    enclosure, so this is what makes the tier findable at all.
[ -f "$MEM/.gitmodules" ] || fail "memory/.gitmodules does not exist; nothing was registered"
registered=$(git config --file "$MEM/.gitmodules" --get "submodule.$TIER.path") || registered=""
[ "$registered" = "$TIER" ] || \
  fail "memory/.gitmodules does not register '$TIER' at its own path (got '$registered')"

# 3. Detached at live — the tier branch model. A tier that came up on a named
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

# 4. Activated. add-tier.sh appends the tier to the manifest as its own final
#    step — the intent already named this exact tier, so no separate agent edit
#    is needed. An unlisted tier would be mounted but dormant.
[ -f "$MEM/.gitlore-tiers" ] || fail "no activation manifest at memory/.gitlore-tiers"
grep -qx "$TIER" "$MEM/.gitlore-tiers" || \
  fail "manifest does not list '$TIER' — the tier is mounted but inactive. Manifest: $(tr '\n' ' ' < "$MEM/.gitlore-tiers")"

# 5. Composed. Activation retriggers the 3-ii compose pass, which splices the
#    tier's pointer lines into the root index with their tier prefix. This is
#    the payoff of the whole flow: the fact is now in always-loaded context.
grep -q "($TIER/reference_acme_staging_db.md)" "$MEM/MEMORY.md" || \
  fail "root index carries no '$TIER/'-prefixed line for the tier's seeded fact; composition did not run"

# 6. The mount committed itself: memory moved by exactly one commit.
baseline=""
[ -f "$EVAL_OUT_DIR/memory-baseline" ] && baseline=$(cat "$EVAL_OUT_DIR/memory-baseline")
[ -n "$baseline" ] || fail "no memory baseline captured; the harness did not record where the store started"

head=$(git -C "$MEM" rev-parse HEAD)
[ "$head" != "$baseline" ] || fail "memory never moved — the mount was not committed"
count=$(git -C "$MEM" rev-list --count "$baseline..HEAD")
[ "$count" = 1 ] || fail "memory moved by $count commits from the baseline, want exactly the one canned mount commit"

# 7. The canned subject names the tier and the url the agent was given.
want_subject="mount $TIER tier from $EVAL_REPO/.tier-remote.git"
subject=$(git -C "$MEM" log -1 --format=%s)
[ "$subject" = "$want_subject" ] || fail "commit subject is '$subject', want '$want_subject'"

# 8. The commit carries the mount's paths and nothing else.
committed=$(git -C "$MEM" diff --name-only "$baseline" HEAD)
for path in .gitmodules .gitlore-tiers "$TIER"; do
  printf '%s\n' "$committed" | grep -qxF "$path" || \
    fail "the mount commit does not include '$path' (committed: ${committed//$'\n'/ })"
done
extra=$(printf '%s\n' "$committed" | grep -vxF -e .gitmodules -e .gitlore-tiers -e "$TIER" -e MEMORY.md || true)
[ -z "$extra" ] || fail "the mount commit carries more than the mount: ${extra//$'\n'/ }"

# 9. Nothing of the mount is left staged but uncommitted.
leftover=$(git -C "$MEM" diff --cached --name-only -- .gitmodules .gitlore-tiers "$TIER")
[ -z "$leftover" ] || \
  fail "the mount is still staged but uncommitted in memory: ${leftover//$'\n'/ }"

# 10. live fast-forwarded to the commit.
live=$(git -C "$MEM" rev-parse live)
[ "$head" = "$live" ] || fail "live not ff-pushed (HEAD=$head live=$live)"

# 11. The parent records the new memory pointer.
# shellcheck disable=SC2034  # read by check_memory_pointer_staged in finish-commit.sh
path_taken="the mount's canned commit"
check_memory_pointer_staged
exit 0
