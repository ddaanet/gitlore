---
description: Install gitlore in this repository
argument-hint: "[memory-path] [precommit-command]"
allowed-tools: ["Bash"]
---

# /gitlore:install

You are installing gitlore in the user's current repository.

## Steps

1. **Confirm context.** Verify you are at the root of a git working tree. Run:
   ```
   git rev-parse --show-toplevel
   ```
   If this fails, tell the user to cd into a git repo and abort.

2. **Gather inputs.** If `$1` was supplied, use it as the memory path; otherwise ask the user, defaulting to `memory`. If `$2` was supplied, use it as the precommit command; otherwise ask the user (e.g. `lefthook run pre-commit`, `pre-commit run --all-files`, etc.).

3. **Run the install orchestrator.**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>"
   ```

   The script exits 0 on success or a partial-but-recoverable install, non-zero on a hard error. On non-zero, surface stderr verbatim and stop.

4. **Summarize.** Tell the user:
   - the memory submodule path,
   - that hooks are wired (which manager),
   - that they should commit the staged changes (`.gitmodules`, memory pointer, `.claude/settings.json`, `.claude/gitlore-hook-setup`, `.gitlore/bin/claude`, `.envrc`) when they're ready,
   - and remind them to run `direnv allow` (or `/gitlore:install-launcher` if they don't use direnv) so memory is redirected into the submodule.

Note: this is the local-only flow. Remote setup is a separate command (added in a later plan).
