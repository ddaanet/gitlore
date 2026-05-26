---
description: Resolve gitlore memory divergence. Activate when a git commit or push fails with output containing "gitlore: memory merge prepared", or when the user invokes /gitlore:resolve.
allowed-tools: ["Bash", "Task", "SendMessage"]
---

# gitlore:resolve

You are resolving a gitlore memory submodule from divergence.

## Entry mode

**Commit-triggered**: The pre-commit hook already emitted a merge directive — it is visible in the output that caused you to invoke this skill. Proceed directly to **Parse directive**.

**Standalone** (user ran `/gitlore:resolve` or state is unclear): Run the resolver:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh"
```

Exit codes:
- `0` — healthy or simple repair complete. Summarize and stop.
- Non-zero + "memory merge prepared" on stderr → proceed to **Parse directive**.
- Non-zero without that → surface stderr verbatim and stop.

## Parse directive

The directive looks like:

```
gitlore: memory merge prepared (flavor=<X>).
gitlore: dispatch the memory-merger sub-agent with state file:
gitlore:   <abs-path-to-state-file>
gitlore: on approval, the sub-agent must run:
gitlore:   cd "<parent-repo>" && bash "<abs-path-to-resolve.sh>" <continuation-subcommand>
```

Extract the state-file path and the full continuation command (the entire `cd ... && bash ... <subcommand>` line, absolute paths intact — the sub-agent runs it verbatim).

## Dispatch memory-merger sub-agent (turn 1 — synthesis)

Use the `Task` tool with `subagent_type: "gitlore:memory-merger"`. Pass both the state-file path and the continuation command in the prompt. The sub-agent synthesizes, runs `git add -A` in the memory worktree, and returns a prose summary. Capture the `agentId`.

## Approve or reject (turn 2 — resume)

Read the sub-agent's summary. Compare against session context: does the synthesis match what we'd expect from the changes seen this session?

Resume via `SendMessage` to the `agentId`:
- If correct: `"approved"`.
- If anything is off: `"rejected: <specific reason>"` — the sub-agent re-synthesizes and returns a new summary; loop back to evaluating it.

Escalate to the user only when session context is insufficient to judge. Treat only a clear, un-negated affirmative as approval — a hedge, a question, or any negation is a rejection.

On approval, the sub-agent runs the continuation command.

## Loop

After the sub-agent exits, run `${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh` again to check for a second flavor. Repeat from **Parse directive** until the script exits 0.

## Resume commit

If this skill was triggered by a commit failure, retry the original git commit now that memory is resolved.

## Summarize

Tell the user what was merged and what state the repo is in now.
