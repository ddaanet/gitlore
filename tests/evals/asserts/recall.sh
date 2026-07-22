#!/usr/bin/env bash
# Assertion: the active-recall round trip put a memory BODY into context.
#
# The mechanism is invisible from the repo alone — a hook read some files and
# injected text — so the proof is the canary: a token that appears nowhere but
# inside the memory body, and which the agent could not answer with unless the
# body actually reached it. The index line the agent starts with deliberately
# does not carry it.
#
# See asserts/memory-commit.sh for the shared contract.
set -uo pipefail

fail() { printf '%s\n' "$1"; exit 1; }

MEM="$EVAL_REPO/memory"
WANT=reference_deploy_lock.md
CANARY=ORBITAL-PANGOLIN-4471

# 1. The request file is one-shot: served or refused, the hook consumes it.
#    Still present means no PostToolBatch hook ever saw it.
[ ! -f "$EVAL_REPO/.claude/gitlore-recall" ] || \
  fail "recall request still present — the recall hook never consumed it"

# 2. The ledger records what this session holds. Path spelled out rather than
#    resolved through scripts/lib/recall.sh: black-box, and it must fail if
#    production moves the ledger.
[ -f "$EVAL_OUT_DIR/session-id" ] || fail "runner captured no session id"
session=$(cat "$EVAL_OUT_DIR/session-id")
safe=$(printf '%s' "$session" | LC_ALL=C sed 's/[^A-Za-z0-9-]/_/g')
ledger=$(git -C "$MEM" rev-parse --git-path "gitlore-recall-$safe")
[ -f "$ledger" ] || fail "no recall ledger at $ledger — nothing was ever recorded as in-context"

# Records are "<hash> <relpath>", hash first so a spaced path survives the split.
hits=$(grep -c " $WANT\$" "$ledger") || hits=0
[ "$hits" -ge 1 ] || \
  fail "ledger does not record $WANT; the request named something else or resolved nothing. Ledger: $(tr '\n' '; ' < "$ledger")"

# 3. Exactly one record. A second means the agent Read the file itself AFTER the
#    hook injected it — the one thing the skill tells it not to do, and the whole
#    reason the ledger exists.
[ "$hits" -eq 1 ] || \
  fail "ledger records $WANT $hits times — the body was fetched and then Read again, spending the context twice"

# 4. The canary reached the answer. This is the only assertion that proves the
#    injected body was actually usable rather than merely delivered.
[ -f "$EVAL_OUT_DIR/turn1.txt" ] || fail "runner captured no turn 1 transcript"
grep -qF "$CANARY" "$EVAL_OUT_DIR/turn1.txt" || \
  fail "the agent's answer does not carry the canary from the memory body — the fact never reached it. Answer: $(tr '\n' ' ' < "$EVAL_OUT_DIR/turn1.txt")"

# 5. It got there via the recall route, not by reading the file. Everything
#    above passes identically if the agent simply opened the body itself: the
#    ledger records plain Reads too, and the answer looks the same. Only the
#    tool calls tell the two apart, and telling them apart is the point — the
#    mechanism exists for the mid-task triggers a Read would never be issued for.
[ -f "$EVAL_OUT_DIR/transcript.jsonl" ] || \
  fail "no session transcript captured; cannot tell an injected body from a self-issued Read"

tools=$(jq -r '.message.content[]? | select(.type == "tool_use")
               | "\(.name)\t\(.input.file_path // "")"' \
          "$EVAL_OUT_DIR/transcript.jsonl")

printf '%s\n' "$tools" | grep -q "^Write	.*/\.claude/gitlore-recall$" || \
  fail "the agent never wrote .claude/gitlore-recall — it answered without going through active recall"

if printf '%s\n' "$tools" | grep -q "^Read	.*/$WANT$"; then
  fail "the agent Read $WANT itself; the skill says not to, and the body was already injected — the context is spent twice"
fi
