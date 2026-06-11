## Current task

New standalone plugin at /Users/david/code/shell-scripting is built, validated, and committed (2 commits) but never trigger-tested in a real session — verify the shell-gotchas skill auto-loads and the shellcheck-on-edit hook fires via `claude --plugin-dir /Users/david/code/shell-scripting`, editing a shell file.

## Open decisions

- Whether to push gitlore's 2 unpushed commits (3b416bb BSD-paste shim fix, fac51d4 enable plugin-dev) — and whether the BSD-paste fix warrants a 0.2.8 release since 0.2.7 ships a macOS-broken shim.
- Whether the shell-scripting plugin gets a LICENSE + marketplace entry, or stays local-only for now.
