#!/usr/bin/env bash
# Assertion: a portable fact was routed into the tier, mirrored, and committed
# in lockstep with the memory store.
#
# Three mechanisms meet here and only an eval sees them meet: the SessionStart
# routing guidance (does the agent put an org-wide fact in the tier instead of
# project memory?), the 3-ii compose pass (does the root index line mirror DOWN
# into the tier's own carrier?), and tier lockstep (does one approved summary
# commit both stores?).
#
# See asserts/memory-commit.sh for the shared contract.
set -uo pipefail

fail() { printf '%s\n' "$1"; exit 1; }

TIER=acme
MEM="$EVAL_REPO/memory"
TIERPATH="$MEM/$TIER"
MSG_FILE="$EVAL_REPO/.claude/gitlore-memory-message"

[ -e "$TIERPATH/.git" ] || fail "tier '$TIER' is not checked out; the fixture did not hold"

# 1. The fact landed in the TIER, not in project memory. Anything but MEMORY.md
#    and the file the fixture seeded is the agent's new fact.
new_file=""
while IFS= read -r f; do
  base=$(basename -- "$f")
  case "$base" in
    MEMORY.md|reference_acme_staging_db.md) continue ;;
  esac
  new_file="$base"
  break
done < <(find "$TIERPATH" -maxdepth 1 -type f -name '*.md')

if [ -z "$new_file" ]; then
  # Name what the agent wrote instead: "the fact went to project memory" and
  # "the agent wrote nothing" are different failures and want different fixes.
  elsewhere=$(find "$MEM" -maxdepth 1 -type f -name '*.md' -exec basename {} \; | tr '\n' ' ')
  fail "no new memory file in the tier — the fact was not routed to $TIER/ (project memory holds: $elsewhere)"
fi

# 2. The root index carries it WITH the tier prefix. That is the contract the
#    session-start guidance states, and what composition keys on.
grep -q "($TIER/$new_file)" "$MEM/MEMORY.md" || \
  fail "root index has no '$TIER/$new_file' pointer line; the agent wrote the body but did not route the index line"

# 3. Composition mirrored it DOWN into the tier's own carrier, unprefixed —
#    which is what makes the fact travel to every other repo mounting the tier.
grep -q "($new_file)" "$TIERPATH/MEMORY.md" || \
  fail "tier index $TIER/MEMORY.md has no line for $new_file; the compose pass did not mirror it down"

# 4. The approval gate ran and the agent left the approved summary for the hook.
[ -f "$MSG_FILE" ] || \
  fail "no commit-msg file (the agent did not write the approved summary after Turn 2)"

mem_before=$(git -C "$MEM" rev-parse HEAD)
tier_before=$(git -C "$TIERPATH" rev-parse HEAD)

# The parent commit is what fires the pre-commit hook: it commits every mounted
# tier and fast-forwards each tier's live BEFORE memory's own `add -A`, so the
# gitlink memory records is never stale.
if ! commit_err=$( (cd "$EVAL_REPO" && git commit --allow-empty -m "chore: trigger eval flow") 2>&1 ); then
  fail "parent git commit failed — ${commit_err//$'\n'/ }"
fi

# 5. Both stores advanced, from the one approved summary.
mem_after=$(git -C "$MEM" rev-parse HEAD)
tier_after=$(git -C "$TIERPATH" rev-parse HEAD)
[ "$mem_after" != "$mem_before" ] || fail "memory store did not advance; nothing was committed"
[ "$tier_after" != "$tier_before" ] || \
  fail "tier did not advance — the fact is written but uncommitted, so it never reaches another repo"

# 6. Both are at their live, the sole travelling ref.
mem_live=$(git -C "$MEM" rev-parse live)
[ "$mem_after" = "$mem_live" ] || fail "memory HEAD ($mem_after) is not at live ($mem_live)"
if ! tier_live=$(git -C "$TIERPATH" rev-parse --verify -q refs/heads/live); then
  fail "tier has no local 'live' branch after the commit"
fi
[ "$tier_after" = "$tier_live" ] || \
  fail "tier HEAD ($tier_after) is not at live ($tier_live); the tier commit did not fast-forward live"

# 7. The commit-msg file is consumed by the hook that used it.
[ ! -f "$MSG_FILE" ] || fail "commit-msg file still present at $MSG_FILE"

# 8. The committed tier actually contains the fact, not just an empty advance.
git -C "$TIERPATH" cat-file -e "HEAD:$new_file" || \
  fail "the tier commit does not contain $new_file"
