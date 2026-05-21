---
description: Diagnose and recover from a partial or broken gitlore remote setup
allowed-tools: ["Bash"]
---

# /gitlore:resolve

You are recovering a gitlore install whose memory remote is missing, unreachable, or partially configured.

## Steps

1. **Confirm context.** Run `git rev-parse --show-toplevel`. If this fails, tell the user to cd into a git repo and abort.

2. **Run the resolver script.**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh"
   ```

   Exits 0 on success (state healthy or repaired). Non-zero means manual intervention is needed; surface stderr verbatim and stop.

3. **Summarize.** Tell the user what state was detected and what action was taken (or what they need to do next).
