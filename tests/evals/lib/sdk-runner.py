#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["claude-agent-sdk"]
# ///
"""SDK-based eval runner for gitlore.

Invokes a Claude agent session with the project's .claude/settings.json hooks
loaded. Unlike `claude --print`, the Agent SDK fires PostToolUse hooks and
injects additionalContext, enabling the full gitlore memory-commit flow.

Usage:
    sdk-runner.py --cwd <path> --prompt <text> [--max-turns N]
"""
import asyncio
import argparse
import sys

from claude_agent_sdk import query, ClaudeAgentOptions, ResultMessage


async def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--cwd", required=True, help="Eval repo working directory")
    p.add_argument("--prompt", required=True, help="User prompt")
    p.add_argument("--max-turns", type=int, default=20)
    args = p.parse_args()

    result = None
    async for msg in query(
        prompt=args.prompt,
        options=ClaudeAgentOptions(
            cwd=args.cwd,
            setting_sources=["project"],
            max_turns=args.max_turns,
        ),
    ):
        if isinstance(msg, ResultMessage):
            result = msg

    if result is None:
        print("eval: no ResultMessage received", file=sys.stderr)
        return 1
    if result.subtype != "success":
        print(
            f"eval: agent stopped with subtype={result.subtype!r}: {result.result}",
            file=sys.stderr,
        )
        return 1
    return 0


sys.exit(asyncio.run(main()))
