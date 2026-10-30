#!/usr/bin/env bash
# Assertion: the memory-commit flow reached its end state.
#
# Contract shared by every script in this directory: run after the agent's turns,
# with cwd anywhere and EVAL_REPO / EVAL_OUT_DIR / EVAL_RUBRIC /
# PLUGIN_ROOT / LIB_DIR in the environment. Exit 0 to pass; exit non-zero with
# the reason on stdout to fail.
#
# The agent's own act commits memory, so the assertion grades the outcome and
# the trace: memory did not move before approval, memory advanced, the session
# invoked the gitlore:commit skill ahead of gitlore-commit, live fast-forwarded,
# the parent records the memory pointer, and the message passes the rubric.
set -uo pipefail

fail() { printf '%s\n' "$1"; exit 1; }

# shellcheck disable=SC1091  # dynamic path resolved at runtime
source "$LIB_DIR/finish-commit.sh"

MEM="$EVAL_REPO/memory"

baseline=""
[ -f "$EVAL_OUT_DIR/memory-baseline" ] && baseline=$(cat "$EVAL_OUT_DIR/memory-baseline")
[ -n "$baseline" ] || fail "no memory baseline captured; the harness did not record where the store started"

# Assertion 0a: memory did not move during turn 1, before the approval message.
check_no_commit_before_approval "$baseline"

path_taken=""   # set by settle_commit_path
# Assertion 0: the approved summary was committed by the agent.
settle_commit_path "$MEM" "$baseline"

# Assertion 1: memory advanced past where the trial started.
[ "$(git -C "$MEM" rev-parse HEAD)" != "$baseline" ] || fail "memory not committed ($path_taken)"

# The commit went through the gitlore:commit skill, not around it.
check_commit_trace

# Assertion 2: live is ff-pushed (HEAD == live).
head=$(git -C "$EVAL_REPO/memory" rev-parse HEAD)
live=$(git -C "$EVAL_REPO/memory" rev-parse live)
[ "$head" = "$live" ] || fail "live not ff-pushed (HEAD=$head live=$live)"

# Assertion 3: the memory pointer is staged in the parent index.
check_memory_pointer_staged

# LLM judge: commit message must match the rubric. Capture the judge's stderr
# (its verdict + one-line reason, and thus the offending message) into the
# failure — else a rubric miss reports THAT but not WHAT.
diff=$(git -C "$EVAL_REPO/memory" show HEAD)
msg=$(git -C "$EVAL_REPO/memory" log -1 --format=%B)
judge_err=$("$LIB_DIR/judge.sh" "$EVAL_RUBRIC" "$diff" "$msg" 2>&1 1>/dev/null)
judge_exit=$?
if [ "$judge_exit" -eq 1 ]; then
  fail "commit message failed judge rubric — ${judge_err//$'\n'/ } — commit msg: ${msg//$'\n'/ }"
elif [ "$judge_exit" -ne 0 ]; then
  fail "judge could not render a verdict (exit $judge_exit) — ${judge_err//$'\n'/ } — commit msg: ${msg//$'\n'/ }"
fi
