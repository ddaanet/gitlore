---
description: Install gitlore in this repository
argument-hint: "[memory-path] [precommit-command]"
allowed-tools: ["Bash"]
---

# /gitlore:install

1. **Gather inputs.** Use `$1` as the memory path if supplied, otherwise ask the user (default: `memory`). Use `$2` as the precommit command if supplied, otherwise ask the user (e.g. `lefthook run pre-commit`, `pre-commit run --all-files`).

2. **Choose the memory remote (D8 — explicit confirmation required).** Determine the proposed remote and confirm before any external action:
   - Run `git config --get remote.origin.url` in the repo. If it returns a URL and `gh auth status` succeeds, the default is **auto-create on GitHub**. Compute the proposed name as `<parent-repo-base>-memory` (the parent origin's repo name with `-memory` appended) and the visibility to match the parent (public parent → public, else private). Show the user the full proposal — owner, repository name, visibility — plus this notice:
     > Memory pushed to this remote may contain any context Claude has recorded — project details, decisions, or incidental session content. Each memory commit is reviewed and confirmed before it's pushed, so you control what goes up.
     Ask for explicit confirmation. Treat only a clear affirmative as approval.
   - If the user prefers a different host or already has an empty remote, ask for the clone URL and use **url mode**.
   - If `gh` is unavailable/unauthed and the user has no URL, or the user declines remote creation, use **local-only mode** (memory works in-repo; a remote can be added later).

3. **Run the installer** with the confirmed mode. This step writes `.gitmodules`, absorbs the memory submodule gitdir under `.git/`, and pushes a remote — all of which the Claude Code command sandbox blocks. Run it with the sandbox **disabled**.
   - Auto-create (default): `"${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>"`
   - Existing URL: `"${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>" url "<remote-url>"`
   - Local-only: `"${CLAUDE_PLUGIN_ROOT}/scripts/install/run.sh" "<memory-path>" "<precommit-cmd>" local`

   If it exits non-zero with a "command sandbox is blocking install" message, re-run the exact command it prints (same invocation, sandbox disabled). Surface stderr verbatim on non-zero exit and stop. Relay stdout and stderr to the user on success.
