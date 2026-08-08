#!/usr/bin/env bash
# Assertion: the agent recalled a memory body from a trigger that surfaced
# MID-TASK, and answered from it.
#
# The canary is a token that appears nowhere but inside the memory body, so an
# answer carrying it proves the body reached context. That alone is not enough:
# CC's own recall would also produce it if the trigger were in the user's
# prompt. So the scenario keeps every trigger token OUT of the prompt — the
# error string only ever appears in a tool result — and this assertion checks
# the ORDER: the body was read after the command that surfaced the error, which
# is the one thing native prompt-time recall cannot do.
#
# See asserts/memory-commit.sh for the shared contract.
set -uo pipefail

fail() { printf '%s\n' "$1"; exit 1; }

WANT=reference_deploy_lock.md
PROBE=nightly-retry.sh
CANARY=ORBITAL-PANGOLIN-4471

[ -f "$EVAL_OUT_DIR/transcript.jsonl" ] || \
  fail "no session transcript captured; cannot tell a mid-task recall from a prompt-time one"

# One line per tool call, in order, numbered: "<n>\t<Tool>\t<path-or-command>".
tools=$(jq -r '.message.content[]? | select(.type == "tool_use")
               | "\(.name)\t\(.input.file_path // .input.command // .input.skill // "")"' \
          "$EVAL_OUT_DIR/transcript.jsonl" | cat -n)

# 1. The scenario has to have happened at all: the agent ran the probe, and the
#    error string reached it as a tool result rather than as prose.
probe_at=$(printf '%s\n' "$tools" | grep -m1 "	Bash	.*$PROBE" | cut -f1) || probe_at=
[ -n "$probe_at" ] || \
  fail "the agent never ran $PROBE, so the mid-task trigger never surfaced — the scenario did not exercise recall"

# 2. The skill was what fetched it. Without this the scenario grades the model's
#    common sense: an agent that simply opened the file on the user's say-so
#    leaves the same answer and the same tool trace minus this one call.
skill_at=$(printf '%s\n' "$tools" | grep -m1 "	Skill	.*recall" | cut -f1) || skill_at=
[ -n "$skill_at" ] || \
  fail "the recall skill was never invoked — the agent answered without it, so this run grades nothing the skill contributes. Tool calls: $(printf '%s' "$tools" | tr '\n' ';')"

# 3. The body was read.
read_at=$(printf '%s\n' "$tools" | grep -m1 "	Read	.*/$WANT\$" | cut -f1) || read_at=
[ -n "$read_at" ] || \
  fail "the agent never Read $WANT — it answered without recalling the body. Tool calls: $(printf '%s' "$tools" | tr '\n' ';')"

# 4. After the probe. A Read that precedes it is CC's native recall firing on
#    the user's prompt, which is exactly the mechanism FR16 exists to supplement
#    — counting it as a pass would grade the harness instead of the skill.
[ "$((read_at))" -gt "$((probe_at))" ] || \
  fail "$WANT was read at call $read_at, before the probe at call $probe_at — that is prompt-time recall, not the mid-task recall this grades"

# 5. The canary reached the answer: delivered AND usable.
[ -f "$EVAL_OUT_DIR/turn1.txt" ] || fail "runner captured no turn 1 transcript"
grep -qF "$CANARY" "$EVAL_OUT_DIR/turn1.txt" || \
  fail "the agent's answer does not carry the canary from the memory body — the fact never reached the answer. Answer: $(tr '\n' ' ' < "$EVAL_OUT_DIR/turn1.txt")"
