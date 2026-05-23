---
description: Diagnose and recover from gitlore memory divergence (semantic merge included)
allowed-tools: ["Bash", "Task", "SendMessage"]
---

# /gitlore:resolve

You are recovering a gitlore memory submodule from divergence — branch-vs-live, local-vs-remote, or a partial recovery state.

## Steps

1. **Confirm context.** Run `git rev-parse --show-toplevel`. If this fails, tell the user to cd into a git repo and abort.

2. **Run the resolver script.**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh"
   ```

   Capture both stdout and stderr. Exit codes:
   - `0` — state healthy or simple repair complete. Summarize and stop.
   - Non-zero with a "memory merge prepared" directive on stderr — proceed to step 3.
   - Non-zero without a directive — surface stderr verbatim, stop.

3. **Parse the directive.** The directive looks like:

   ```
   gitlore: memory merge prepared (flavor=<X>).
   gitlore: dispatch the memory-merger sub-agent with state file:
   gitlore:   <abs-path-to-state-file>
   gitlore: on approval, the sub-agent must run:
   gitlore:   cd "<parent-repo>" && bash "<abs-path-to-resolve.sh>" <continuation-subcommand>
   ```

   Extract the state-file path and the full continuation command (the entire `bash "..." <subcommand>` line, absolute paths intact — the sub-agent runs it verbatim).

4. **Dispatch the `memory-merger` sub-agent (turn 1 — synthesis).**

   Use the `Task` tool with `subagent_type: "gitlore:memory-merger"` (the bare `memory-merger` form does not resolve — CC namespaces plugin agents under the plugin name). Pass two inputs in the prompt: the state-file path AND the full continuation command from the directive.

   The sub-agent will synthesize, run `git add -A` in the memory worktree, and **return** a prose summary as its final message for this turn. It will not run the continuation yet. Capture the `agentId` from the dispatch result.

5. **Approve or reject (turn 2 — resume).**

   Read the sub-agent's return message. Compare against session context: does the synthesis match what we'd expect from the changes you've seen this session?

   Resume the sub-agent via `SendMessage` to its `agentId`:
   - If the synthesis is correct: `message: "approved"`.
   - If anything is off: `message: "rejected: <specific reason>"`. The sub-agent will re-synthesize and return a new summary; loop back to evaluating it.

   Escalate to the user only when session context is insufficient to judge.

   On approval, the sub-agent runs the continuation command and returns a one-line result.

6. **After the sub-agent exits**, run `${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh` again to check for a second flavor or a loop continuation. Repeat steps 2-6 until the script exits 0.

7. **Summarize.** Tell the user what was merged and what state the repo is in now.
