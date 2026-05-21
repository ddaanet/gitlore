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
   gitlore:   <abs-path>
   gitlore: on approval, the sub-agent must run:
   gitlore:   bash "$CLAUDE_PLUGIN_ROOT/scripts/resolve.sh" <continuation>
   ```

   Extract the state-file path. Save the continuation command for verification only — the sub-agent will run it itself.

4. **Dispatch the `memory-merger` sub-agent.**

   Use the `Task` tool with `subagent_type: "memory-merger"`. Pass the state-file path as the only input.

5. **Answer the sub-agent's approval request.**

   The sub-agent will SendMessage with a prose summary. Read it. Compare against session context: does the synthesis match what we'd expect from the changes you've seen this session? If so, answer "approved". If anything is off, answer "rejected: <reason>" and let the sub-agent retry.

   Escalate to the user only when session context is insufficient.

6. **After the sub-agent exits**, run `${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh` again to check for a second flavor or a loop continuation. Repeat steps 2-6 until the script exits 0.

7. **Summarize.** Tell the user what was merged and what state the repo is in now.
