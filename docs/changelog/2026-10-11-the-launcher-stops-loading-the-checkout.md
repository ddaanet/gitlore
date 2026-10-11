# 2026-10-11 — The launcher stops loading the checkout

**`GITLORE_AUTO_CLAUDE_PLUGIN_DIR` is removed from the launcher shim.** With the
variable set and a `.claude-plugin/plugin.json` in the cwd, the shim prepended
`--plugin-dir .` so a plugin author's session loaded the checkout instead of the
marketplace cache. The variable is now ignored: the shim reads nothing but
`GITLORE_LAUNCHED`, and a shell that still exports it gets a session that loads
the installed plugin. There is no deprecation period and no warning — the opt-in
was default-off and documented only in the launcher reference.

The reason is what Claude Code does with an inline plugin root. Every path under
one is a sensitive file to its permission layer, and `--plugin-dir .` makes the
repository root that root, so every edit anywhere in the repo is held:
accept-edits prompts regardless, auto mode reports that the classifier gave no
verdict, and a subagent with no one to prompt stalls. Observed here across two
sessions of this repo, which exported the variable from its own `.envrc`:
launched with it, every in-repo `Write` and `Edit` was refused while writes to
the temp directory passed; launched without it, the same edit lands. The
launcher's argv is not visible from the sandboxed shell, so the pairing rests on
the session environment and the shim's own condition, not on a read of the
command line.

**gitlore dogfoods through the toolkit's shim instead.** `plugin-dev/bin/claude`
loads the plugin from `dist/plugin/`, a copy `just dogfood` promotes from the
working tree, and chains to the next `claude` on `PATH` — gitlore's launcher,
which still injects the memory redirect. The copy is the inline root, so the
sensitive-path rule covers `dist/plugin/` and leaves the checkout editable.
`.envrc` puts `plugin-dev/bin` on `PATH` last, where direnv's prepending makes
it the first `claude` found; `.gitignore` carries `/dist/plugin/`, without which
the sync refuses; and `.claude/settings.json` gains the toolkit's two dogfood
hooks, with its version-guard command requoted for a path with a space.

A change to plugin code is live after `just dogfood`, and an agent definition or
hook event needs a relaunch as well.
