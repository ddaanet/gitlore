---
description: Install gitlore in this repository
argument-hint: "[memory-path] [precommit-command]"
allowed-tools: ["Bash"]
---

# /gitlore:install

1. **Gather inputs.** Use `$1` as the memory path if supplied, otherwise ask the user (default: `memory`). Use `$2` as the precommit command if supplied, otherwise ask the user (e.g. `lefthook run pre-commit`, `pre-commit run --all-files`).

2. **Run the installer.** This step writes `.gitmodules`, absorbs the memory
   submodule gitdir under `.git/`, and pushes a remote — all of which the Claude
   Code command sandbox blocks. Run it with the sandbox **disabled**.
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>"
   ```
   If it exits non-zero with a "command sandbox is blocking install" message,
   re-run the exact command it prints (the same invocation, sandbox disabled).
   Surface stderr verbatim on non-zero exit and stop. Relay stdout and stderr to
   the user on success.
