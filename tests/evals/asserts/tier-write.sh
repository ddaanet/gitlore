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
# Captured first, not `< <(find …)`: a process substitution hides find's exit
# status, and an unreadable tier would then read as "the agent wrote nothing".
md_files=$(find "$TIERPATH" -maxdepth 1 -type f -name '*.md') \
  || fail "could not list $TIERPATH — the fixture did not hold"
new_file=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  base=$(basename -- "$f")
  case "$base" in
    MEMORY.md|reference_acme_staging_db.md) continue ;;
  esac
  new_file="$base"
  break
done <<<"$md_files"

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

# 4. The approval gate ran, and the approved summary is what commits both stores.
#
# FR11 gives the agent two correct ways to finish once the user approves, and
# which one it picks is not what this scenario grades:
#
#   - write the summary and STOP — the user's next parent commit consumes it;
#   - write the summary AND the commit trigger — the PostToolBatch hook commits
#     on the spot, which is the standalone path memory-commit-batch.sh exists
#     for and the one a session with no parent commit pending must take.
#
# Grading the stop-point instead of the outcome makes this scenario fail
# whenever the agent picks the second, which is a defect in the assertion, not
# in the flow: the fact is committed, the summary is the commit message, and the
# tier travelled. So establish WHICH path ran, fire the parent commit only if
# the flow is still waiting on one, and grade the same end state either way.
baseline=""
[ -f "$EVAL_OUT_DIR/memory-baseline" ] && baseline=$(cat "$EVAL_OUT_DIR/memory-baseline")
[ -n "$baseline" ] || fail "no memory baseline captured; the harness did not record where the store started"

if [ -f "$MSG_FILE" ]; then
  # Stop path. The parent commit fires the pre-commit hook, which commits every
  # mounted tier and fast-forwards each tier's live BEFORE memory's own `add -A`,
  # so the gitlink memory records is never stale.
  if ! commit_err=$( (cd "$EVAL_REPO" && git commit --allow-empty -m "chore: trigger eval flow") 2>&1 ); then
    fail "parent git commit failed — ${commit_err//$'\n'/ }"
  fi
  path_taken="the agent stopped after writing the summary; the parent commit consumed it"
else
  # No summary on disk. Either the hook already consumed it — in which case
  # memory has moved — or the agent never wrote one, which is a real failure and
  # has two distinguishable causes worth naming separately.
  mem_now=$(git -C "$MEM" rev-parse HEAD)
  if [ "$mem_now" = "$baseline" ]; then
    if [ -f "$EVAL_REPO/.claude/gitlore-commit-memory" ]; then
      fail "no commit-msg file, but the commit trigger IS present — the agent asked for the commit without ever writing the approved summary, so the batch hook is parked waiting for it"
    fi
    fail "no commit-msg file and no trigger, and memory never moved — the agent did not write the approved summary after Turn 2"
  fi
  path_taken="the agent wrote the summary and the trigger; the batch hook committed"
fi

# 5. Memory advanced past where the trial started.
mem_after=$(git -C "$MEM" rev-parse HEAD)
[ "$mem_after" != "$baseline" ] || fail "memory store did not advance ($path_taken); nothing was committed"

# 6. The tier committed the fact itself. Checking the file is in the tier's
#    HEAD tree beats checking the tier merely advanced: an advance can be an
#    empty or unrelated commit, and what has to travel to another repo is the
#    body, not the ref move.
tier_after=$(git -C "$TIERPATH" rev-parse HEAD)
git -C "$TIERPATH" cat-file -e "HEAD:$new_file" || \
  fail "the tier commit does not contain $new_file ($path_taken) — the fact is written but uncommitted, so it never reaches another repo"
tier_dirty=$(git -C "$TIERPATH" status --porcelain)
[ -z "$tier_dirty" ] || \
  fail "tier still has uncommitted changes after the flow ($path_taken) — ${tier_dirty//$'\n'/ }"

# 7. Lockstep: the gitlink memory COMMITTED for the tier is the tier's new HEAD.
#    Checked against the committed tree, and BEFORE the uncommitted-remainder
#    check below — a one-behind gitlink also shows up as a dirty memory tree, so
#    ordering these the other way round would report the lag as generic dirt and
#    leave this check unable to fail at all.
mem_gitlink=$(git -C "$MEM" rev-parse "HEAD:$TIER") || \
  fail "memory's committed tree has no gitlink for tier '$TIER'"
[ "$mem_gitlink" = "$tier_after" ] || \
  fail "memory committed a stale gitlink for '$TIER' ($mem_gitlink) while the tier is at $tier_after ($path_taken) — the one-behind lag: the tier's fact will not reach a fresh clone"

# 8. No uncommitted remainder in memory — a half-committed store leaves the fact
#    stranded locally. Everything gitlink-shaped is already ruled out above, so
#    what reaches here is a memory file the flow failed to include.
mem_dirty=$(git -C "$MEM" status --porcelain)
[ -z "$mem_dirty" ] || \
  fail "memory still has uncommitted changes after the flow ($path_taken) — ${mem_dirty//$'\n'/ }"

# 9. Both are at their live, the sole travelling ref.
mem_live=$(git -C "$MEM" rev-parse live)
[ "$mem_after" = "$mem_live" ] || fail "memory HEAD ($mem_after) is not at live ($mem_live)"
if ! tier_live=$(git -C "$TIERPATH" rev-parse --verify -q refs/heads/live); then
  fail "tier has no local 'live' branch after the commit"
fi
[ "$tier_after" = "$tier_live" ] || \
  fail "tier HEAD ($tier_after) is not at live ($tier_live); the tier commit did not fast-forward live"

# 10. The commit-msg file is consumed by whichever hook used it. One approval is
#     spent once: a summary left on disk would be re-applied to the next commit.
[ ! -f "$MSG_FILE" ] || fail "commit-msg file still present at $MSG_FILE ($path_taken)"

# 11. The rubric. The scenario grades whether the commit message describes the
#     fact that was actually recorded, and the fact lives in the TIER commit —
#     memory's own commit is a gitlink bump plus an index line, which says
#     nothing about Sentry. Both stores carry the same approved summary, so
#     judging the tier commit judges the summary the user approved.
tier_diff=$(git -C "$TIERPATH" show HEAD)
tier_msg=$(git -C "$TIERPATH" log -1 --format=%B)
judge_err=$("$LIB_DIR/judge.sh" "$EVAL_RUBRIC" "$tier_diff" "$tier_msg" 2>&1 1>/dev/null)
judge_exit=$?
if [ "$judge_exit" -eq 1 ]; then
  fail "commit message failed judge rubric — ${judge_err//$'\n'/ } — commit msg: ${tier_msg//$'\n'/ }"
elif [ "$judge_exit" -ne 0 ]; then
  fail "judge could not render a verdict (exit $judge_exit) — ${judge_err//$'\n'/ } — commit msg: ${tier_msg//$'\n'/ }"
fi
