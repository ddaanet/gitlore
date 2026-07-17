## Current task

The eval-harness choice is the only work left open — `tests/evals/` docs and memory now state the verified facts, but the harness itself is untouched pending the decision below.

## Open decisions

- Eval harness: drop the Agent SDK for a `claude --print --resume` runner, keep `sdk-runner.py` as-is, or rewrite it onto `ClaudeSDKClient`. The rationale the SDK was chosen for is false — `query()` is stateless and spawns per call, so both harnesses re-prime context every turn; measured warm, the SDK's real edge is ~$0.05 and ~10s per two-turn trial (process startup, plus ~7k context because the CLI loads user settings while the runner passes `setting_sources=["project"]`). Recommendation: switch — that edge does not pay for a `uv` + Python + `claude-agent-sdk` dependency in an otherwise bash/bats suite, and the replacement is ~10 lines of bash. `ClaudeSDKClient` is the only path that would deliver genuine process persistence, at the cost of keeping the dependency.
