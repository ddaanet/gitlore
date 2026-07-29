## Current task

The `/gitlore:push` feature (D20) is built, documented and green — 632 cases, lint clean. What remains is dogfooding it against this repo's own stores, which are each one commit ahead of their remotes and strict fast-forwards, so the first real-target run publishes rather than merges.

## Open decisions

- Dogfood now or next session. Running `CLAUDE_PLUGIN_ROOT=/Users/david/code/gitlore bash scripts/push-memory.sh` exercises the script immediately but not the real invocation path; waiting for a session where `SessionStart` has seeded `gitlore.pushCommand` and the plugin is reloaded tests `/gitlore:push` itself, which is what a user would actually type.
- `memory/MEMORY.md` is ~21.8KB against a 17.1KB soft target (24.4KB is the hard truncation line). Closing the gap needs either dropping some facts' index lines, orphaning them from recall, or merging distinct facts into shared files; prose-tightening alone returns ~1-1.5KB per pass. Needs a human call on what is droppable or mergeable.