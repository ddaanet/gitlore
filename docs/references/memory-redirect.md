# Memory redirect — decision D10

The launcher shim that points Claude Code's auto-memory at the repo's `memory/`
store, and the two places it can be installed from. Part of the install and
launch mechanism in [installation.md](installation.md).

- **D10** — the memory redirect is a launch-time `--settings` shim, not project
  settings

---

## Memory Redirect Launcher

Claude Code's native auto-memory writes to
`~/.claude/projects/<sanitized-cwd>/memory/` unless `autoMemoryDirectory` is set
in an honored settings tier. Project settings are *not* honored (D10), so the
only per-project, non-global mechanism is the `--settings` flag at launch. The
launcher is a thin `claude` shim that injects it transparently — the user keeps
typing `claude`, and memory lands in the submodule.

**One shim, two placements.** The shim body is identical in both modes; only how
it lands on `PATH` differs. It is `#!/usr/bin/env sh`:

```sh
#!/usr/bin/env sh
# real claude = next `claude` on PATH after stripping my own dir
self=$(cd "$(dirname "$0")" && pwd)
newpath=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$self" | paste -sd:)
real=$(PATH="$newpath" command -v claude) || { echo "gitlore: real claude not found" >&2; exit 127; }

# already injected upstream? pass through (composability, anti-double-inject, anti-recursion)
[ -n "$GITLORE_LAUNCHED" ] && exec "$real" "$@"

# opt-in: load the plugin from the checkout you're standing in, not the marketplace cache
if [ -n "$GITLORE_AUTO_CLAUDE_PLUGIN_DIR" ] && [ -f .claude-plugin/plugin.json ]; then
  set -- --plugin-dir . "$@"
fi

# in a gitlore-enabled repo? cheap git checks first, so jq only runs for actual gitlore repos
root=$(git rev-parse --show-toplevel 2>/dev/null)
mempath=$(git config --file "$root/.gitmodules" submodule.gitlore-memory.path 2>/dev/null)
[ -n "$root" ] && [ -n "$mempath" ] || exec "$real" "$@"          # no gitlore submodule → passthrough
[ "$(jq -r '.gitlore.enabled // false' "$root/.claude/settings.json" 2>/dev/null)" = true ] \
  || exec "$real" "$@"                                            # submodule present but disabled → passthrough

json=$(jq -nc --arg p "$root/$mempath" '{autoMemoryDirectory:$p}')
export GITLORE_LAUNCHED=1
exec "$real" --settings "$json" "$@"
```

- **Real-claude resolution.** The shim strips its own directory from `PATH`,
  then takes the next `claude`. That next entry is normally Claude Code's own
  version-selector launcher (`~/.local/bin/claude`), so version selection is
  preserved — the shim chains to it rather than pinning a version.
- **`GITLORE_LAUNCHED` sentinel.** Set before exec. Does triple duty: (a) when
  both shims are on `PATH`, the repo-local one runs first, execs the global one
  which sees the sentinel and passes through — no double injection; (b) guards
  against any accidental recursion; (c) lets `SessionStart` detect a plain
  `claude` launch (sentinel unset) and warn loudly instead of silently stranding
  memory.
- **`GITLORE_AUTO_CLAUDE_PLUGIN_DIR` (opt-in, default off).** When the var is
  non-empty *and* the cwd holds a `.claude-plugin/plugin.json`, the shim
  prepends `--plugin-dir .`, so Claude Code loads the plugin from the checkout
  you are standing in rather than the marketplace cache — which lags the repo at
  the same version string, making plugin changes untestable without a reinstall.
  Default-off because silently shadowing an installed plugin whenever a user
  cd's into its source tree would mask a released version with dirty
  working-tree code; opting in is a one-line rc export. Injected via
  `set -- --plugin-dir . "$@"` before the repo checks, so it applies on every
  exec path including passthrough — a plugin checkout need not be a gitlore
  repo. The `GITLORE_LAUNCHED` sentinel still short-circuits first, so an
  upstream shim's decision wins.
- **Path built with `jq`.** Handles spaces/quoting safely; computed at runtime
  so committed shims stay portable across clones. `--settings` loads an
  *additional* settings tier (`flagSettings`), so only `autoMemoryDirectory` is
  overridden; all other settings still resolve from their normal tiers.

**Placement A — repo-local, direnv (default).** `/gitlore:install` emits two
**committed** files: `.gitlore/bin/claude` (the shim) and `.envrc`. The `.envrc`
puts `.gitlore/bin` at the **front** of `$PATH` so the shim shadows the real
`claude`, which is what direnv's `PATH_add .gitlore/bin` does. A fresh `.envrc`
gets `source_up_if_exists` as its first line so parent-directory configs are
inherited. With an existing `.envrc`, direnv evaluates top-to-bottom and each
`PATH_add` prepends, so the *last* one wins the front slot — gitlore's line is
inserted after any pre-existing `PATH_add` (idempotent no-op if already
present). After a one-time `direnv allow` the shim is on `PATH` inside the repo
tree only, subdirectories included, and both files travel with the repo. The
path is namespaced under `.gitlore/bin/` to avoid colliding with a project's own
`bin/`.

**Placement B — global shim, no-direnv fallback (automatic).** When direnv is
not found during install, `run.sh` runs `scripts/install/global-shim.sh`, which
drops the *same shim* at `~/.gitlore/bin/claude` and **prints** (does not
auto-append) the one `PATH` line for the user's shell rc (e.g.
`set -gx PATH ~/.gitlore/bin $PATH` for fish). Per-repo installs never touch it
otherwise. The gitlore-repo detection is generic, so this one shim
auto-activates in any gitlore repo and no-ops everywhere else. It covers users
without direnv, and launches from outside an allowed directory.

**D10 — Memory redirect via a launch-time `--settings` shim, not project
settings**

Claude Code resolves `autoMemoryDirectory` only from the `policySettings`,
`flagSettings`, and `userSettings` tiers (verified by reading the resolver in
the CC binary, v2.1.150). Project-level `.claude/settings.json` and
`.claude/settings.local.json` are deliberately excluded for security — a
checked-in repo setting must not be able to redirect where a user's memory is
written. The discard is silent: a project tier carrying the key produces no
diagnostic, and memory simply lands in the default
`~/.claude/projects/<sanitized-cwd>/memory/` dir (Rejected Alternatives).

The honored tiers are either global (`userSettings`, `policySettings`) or
per-launch (`flagSettings`, via `--settings`). Per-project redirection without
polluting other projects therefore requires supplying the value at launch. A
thin `claude` shim injects `--settings '{"autoMemoryDirectory":…}'`
transparently (see Memory Redirect Launcher). This keeps the value proposition
intact — the user invokes Claude Code normally and uses its *native*
auto-memory; only the storage directory is redirected, with no cowork semantics.

Because an unredirected launch strands memory silently, the `SessionStart`
launcher guard (sentinel `GITLORE_LAUNCHED`) detects one and warns.

## Rejected alternatives

**`autoMemoryDirectory` in `.claude/settings.json` or
`.claude/settings.local.json`.** Silently ignored — CC honours the key only from
`policySettings`, `flagSettings` and `userSettings`, never a project tier.
Observed, not inferred: with the key written there, memory lands in the default
directory and nothing reports the discard (D10).

**`autoMemoryDirectory` in global `~/.claude/settings.json`.** Honoured, but
global: every project's auto-memory would redirect into one repo's submodule.

**`CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` via `.envrc`.** Highest precedence and
per-project scopable, but it carries cowork semantics — it disables the native
memory-write auto-allow and can inject cowork guidelines into the system prompt.
`--settings` feeds the identical setting with none of that (D10).

**An explicit `gitlore` launch command instead of shadowing `claude`.** Breaks
the value proposition: users would have to remember a new command. The shim
keeps them typing `claude`.
