#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["claude-agent-sdk"]
# ///
"""SDK-based eval runner for gitlore.

Invokes a Claude agent session with the project's .claude/settings.json hooks
loaded. Unlike `claude --print`, the Agent SDK fires PostToolUse hooks and
injects additionalContext, enabling the full gitlore memory-commit flow.

Two-turn flow:
  Turn 1 — agent edits memory, runs precommit command, hook injects
            additionalContext, agent summarises pending changes and stops.
  Turn 2 — eval sends the approval message; agent writes commit-msg file.

Usage:
    sdk-runner.py --cwd <path> --prompt <text> --approval <text> [--max-turns N]
    sdk-runner.py --probe --cwd <path>   # connectivity check only
"""
import asyncio
import argparse
import sys

from claude_agent_sdk import query, ClaudeAgentOptions, ResultMessage


async def run_turn(
    prompt: str,
    cwd: str,
    max_turns: int,
    session_id: str | None = None,
) -> ResultMessage | None:
    opts = ClaudeAgentOptions(
        cwd=cwd,
        setting_sources=["project"],
        max_turns=max_turns,
        permission_mode="bypassPermissions",
        **({"resume": session_id} if session_id else {}),
    )
    result = None
    async for msg in query(prompt=prompt, options=opts):
        if isinstance(msg, ResultMessage):
            result = msg
    return result


async def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--cwd", required=True, help="Working directory")
    p.add_argument("--prompt", help="Turn-1 user prompt")
    p.add_argument("--approval", help="Turn-2 approval message")
    p.add_argument("--max-turns", type=int, default=20)
    p.add_argument("--probe", action="store_true",
                   help="Test Claude Code API connectivity and exit (no eval run)")
    args = p.parse_args()

    if args.probe:
        t = await run_turn("reply with the single word ok", args.cwd, max_turns=1)
        if t is None:
            print("probe: no response from Claude Code API", file=sys.stderr)
            return 1
        if t.subtype != "success":
            print(f"probe: API error (subtype={t.subtype!r})", file=sys.stderr)
            return 1
        return 0

    if not args.prompt or not args.approval:
        p.error("--prompt and --approval are required unless --probe is set")

    # Turn 1: agent edits memory, runs precommit command, receives hook
    # additionalContext, summarises changes, stops waiting for approval.
    t1 = await run_turn(args.prompt, args.cwd, args.max_turns)
    if t1 is None:
        print("eval: turn 1 yielded no ResultMessage", file=sys.stderr)
        return 1
    if t1.subtype != "success":
        print(f"eval: turn 1 failed subtype={t1.subtype!r}: {t1.result}", file=sys.stderr)
        return 1

    session_id = t1.session_id

    # Turn 2: user approves; agent writes commit-msg file.
    t2 = await run_turn(args.approval, args.cwd, args.max_turns, session_id=session_id)
    if t2 is None:
        print("eval: turn 2 yielded no ResultMessage", file=sys.stderr)
        return 1
    if t2.subtype != "success":
        print(f"eval: turn 2 failed subtype={t2.subtype!r}: {t2.result}", file=sys.stderr)
        return 1

    return 0


sys.exit(asyncio.run(main()))
