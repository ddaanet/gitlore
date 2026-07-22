#!/usr/bin/env bash
# Assertion: the FR11 memory-commit flow reached its end state.
#
# Contract shared by every script in this directory: run after the agent's turns,
# with cwd anywhere and EVAL_REPO / EVAL_OUT_DIR / EVAL_RUBRIC / EVAL_TRIGGER /
# PLUGIN_ROOT / LIB_DIR in the environment. Exit 0 to pass; exit non-zero with
# the reason on stdout to fail.
#
# This script owns the parent `git commit` too: firing it is part of the flow
# being graded (it is what runs the pre-commit hook), and flows without an
# approval gate must not have one fired at them.
set -uo pipefail

fail() { printf '%s\n' "$1"; exit 1; }

# The approved-summary IPC file the agent writes and the pre-commit hook
# consumes. Spelled out rather than resolved via scripts/lib/util.sh: these
# assertions are black-box, and must fail if production moves the file.
MSG_FILE="$EVAL_REPO/.claude/gitlore-memory-message"

# Assertion 0: agent completed its share of the gitlore flow.
# PTU path: agent wrote commit-msg and stopped; the commit below will consume it.
#   → commit-msg must be present.
# Pre-commit failure path: agent retried git commit after approval; the hook ran,
#   committed memory, and deleted commit-msg as part of completing the parent commit.
#   → commit-msg must be absent (still present = agent wrote it but did not retry).
if [ "$EVAL_TRIGGER" = "precommit_failure" ]; then
  [ ! -f "$MSG_FILE" ] || \
    fail "commit-msg still present after Turn 2 (agent wrote commit-msg but did not retry the commit)"
else
  [ -f "$MSG_FILE" ] || \
    fail "no commit-msg file (agent did not write it after receiving additionalContext)"
fi

# Parent commit fires the gitlore pre-commit hook, which commits memory
# (including any required merge steps and ff-push to live) before the parent
# commit can proceed.
if ! commit_err=$( (cd "$EVAL_REPO" && git commit --allow-empty -m "chore: trigger eval flow") 2>&1 ); then
  fail "parent git commit failed — ${commit_err//$'\n'/ }"
fi

# Assertion 1: memory has ≥2 commits (initial + the new one).
count=$(git -C "$EVAL_REPO/memory" log --oneline | wc -l | tr -d ' ')
[ "$count" -ge 2 ] || fail "memory not committed (found $count commit(s))"

# Assertion 2: live is ff-pushed (HEAD == live).
head=$(git -C "$EVAL_REPO/memory" rev-parse HEAD)
live=$(git -C "$EVAL_REPO/memory" rev-parse live)
[ "$head" = "$live" ] || fail "live not ff-pushed (HEAD=$head live=$live)"

# Assertion 3: commit-msg temp file was consumed and deleted.
[ ! -f "$MSG_FILE" ] || fail "commit-msg file still present at $MSG_FILE"

# LLM judge: commit message must match the rubric. Capture the judge's stderr
# (its verdict + one-line reason, and thus the offending message) into the
# failure — else a rubric miss reports THAT but not WHAT.
diff=$(git -C "$EVAL_REPO/memory" show HEAD)
msg=$(git -C "$EVAL_REPO/memory" log -1 --format=%B)
if ! judge_err=$("$LIB_DIR/judge.sh" "$EVAL_RUBRIC" "$diff" "$msg" 2>&1 1>/dev/null); then
  fail "commit message failed judge rubric — ${judge_err//$'\n'/ } — commit msg: ${msg//$'\n'/ }"
fi
