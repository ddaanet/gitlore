---
description: Install the gitlore launcher globally (no-direnv fallback)
allowed-tools: ["Bash"]
---

# /gitlore:install-launcher

One-time, machine-level setup of the gitlore launcher for users who don't use direnv, or who launch Claude Code from outside an allowed directory. Placement A (`/gitlore:install` + `direnv allow`) is preferred; this is the fallback.

1. Run:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/install/global-shim.sh"
   ```
2. Relay the printed `PATH` instruction to the user **verbatim**. Tell them to add that line to their shell rc and restart their shell. Do not edit their rc yourself.
