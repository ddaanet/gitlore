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
# real claude = next `claude` on PATH after stripping my own dir. Each entry is
# resolved to the physical form $self is already in: a `//`, a trailing `/`, a
# `..` or a symlink spells one directory two ways, a strip matching raw
# spellings leaves the shim on PATH, and the exec below then re-enters it with
# no exit. macOS `$TMPDIR` ends in `/`, so paths built from it carry the first.
self=$(cd "$(dirname "$0")" && pwd -P)
newpath=
oldifs=$IFS
IFS=:
for d in $PATH; do
  if [ -d "$d" ]; then n=$(cd "$d" && pwd -P); else n=$d; fi
  [ "$n" = "$self" ] || newpath="${newpath:+$newpath:}$d"
done
IFS=$oldifs
real=$(PATH="$newpath" command -v claude) || { echo "gitlore: real claude not found" >&2; exit 127; }

# already injected upstream? pass through (composability, anti-double-inject, anti-recursion)
[ -n "$GITLORE_LAUNCHED" ] && exec "$real" "$@"

# in a gitlore-enabled repo? cheap git checks first, so jq only runs for actual gitlore repos
root=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$root" ] || exec "$real" "$@"                               # not in a repo → passthrough
mempath=$(git config --file "$root/.gitmodules" submodule.gitlore-memory.path)
[ -n "$mempath" ] || exec "$real" "$@"                            # no gitlore submodule → passthrough
[ "$(jq -r '.gitlore.enabled // false' "$root/.claude/settings.json" 2>/dev/null)" = true ] \
  || exec "$real" "$@"                                            # submodule present but disabled → passthrough

# containment (see "Memory-path containment" below; full text in
# scripts/install/launcher-shim): control characters, then lexical, then
# physical, then the gitlink — any failure prints one line and execs "$real" "$@"

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
- **Path built with `jq`.** Handles spaces/quoting safely; computed at runtime
  so committed shims stay portable across clones. `--settings` loads an
  *additional* settings tier (`flagSettings`), so only `autoMemoryDirectory` is
  overridden; all other settings still resolve from their normal tiers.
- **Memory-path containment.** `mempath` and `gitlore.enabled` both come from
  files the checkout controls, and the redirect gives `mempath` the standing of
  a value the user typed — and Claude Code auto-allows writes under
  `autoMemoryDirectory`, so a memory directory of `.claude` would let a session
  rewrite its own hooks unprompted. The shim therefore injects only the memory
  submodule's own path: strictly inside the repo, outside its control
  directories — `.git`, `.gitlore`, and `.claude` except `.claude/memory`, the
  documented alternative layout (design.md, Memory Submodule).
  `git config --file` returns a `.gitmodules` path verbatim — `../x`, `a/../..`
  and `/etc/x` alike; git's own `..` rejection applies when it adds a submodule,
  not on a read. Claude Code then takes any absolute path, normalizes its `..`
  away, and neither resolves symlinks nor compares it with the project (read in
  the CC 2.1.310 resolver). The checks run cheapest first. A path with a control
  character is refused without being shown, since the refusal line reaches the
  terminal; every other refusal prints the path with `printf '%s'`. Then
  lexical, because before `git submodule update --init` the memory directory
  does not exist and the shim still injects it: an absolute `mempath` is
  refused, and so is any `..` or `.` *component* — matched as `/../` or `/./` in
  `/$mempath/`, so a name such as `my..memory` passes — and any `.git` or
  `.gitlore` component, and any `.claude` component not followed directly by
  `memory` — so `.claude/memory` passes while `.claude` itself and
  `.claude/skills`, `commands`, `agents` or `hooks`, which Claude Code loads, do
  not. All compared case-insensitively, because macOS filesystems are. Then
  physical: the nearest existing directory on the memory path (the memory
  directory itself once initialised) is resolved with `cd … && pwd -P` and must
  sit under the physical root; that resolved directory plus the part of the path
  not created yet must not be the root itself and must pass the same
  control-directory rule. That catches a symlinked memory directory and a
  symlinked parent that a not-yet-created memory directory would land under. A
  symlink met on the way up that names no directory is refused outright. Last,
  the one git call: `git ls-files -s` on the literal path must return only
  mode-160000 gitlink entries for exactly `mempath` — one, or one per stage
  while a parent merge leaves the gitlink unmerged, which is when the user
  launches claude to resolve it. A fresh clone has the gitlink before the
  submodule is initialised, so the uninitialised case still injects, while a
  plain directory, a non-normalized spelling (`./memory`, `memory/`) and any
  path git refuses to index are refused, as is a path holding `"` or `\`, which
  git C-quotes in that output whatever `core.quotePath` says. A refusal is the
  one non-silent passthrough: one `gitlore:` line on stderr names the path and
  the reason, then the real `claude` runs with the original arguments, no
  `--settings` and `GITLORE_LAUNCHED` unset — so the `SessionStart` guard also
  reports the unredirected launch, and with both placements on `PATH` each
  prints the line.

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

**Refreshing a placed shim.** Both placements are copies of
`scripts/install/launcher-shim`, and nothing rewrites them on a plugin update or
at session start. Re-running `/gitlore:install` from the main worktree root
(with the memory path the repo uses, if not `memory`) is the refresh path: the
install is idempotent, `emit-launcher.sh` overwrites `.gitlore/bin/claude` and
stages it for the user to commit, and on a machine without direnv
`global-shim.sh` overwrites `~/.gitlore/bin/claude`. A global shim on a machine
that has since gained direnv is not rewritten by the install;
`CLAUDE_PLUGIN_ROOT=<plugin dir> bash <plugin dir>/scripts/install/global-shim.sh`
rewrites it directly.

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

**Containment by canonicalizing the memory directory alone.** `cd` fails before
the submodule is initialised, so the shim would either pass through — silently
disabling the redirect on every fresh clone — or skip the check. The lexical
checks hold without the directory, and the physical check runs on its nearest
existing ancestor.

**Containment under the root as the whole test.** Inside the repo is not
harmless: the root itself, `.git`, `.claude` and `.gitlore` all sit under it,
and auto-allowed writes there reach hooks and settings. The gitlink requirement
pins the path to the submodule, and the component checks cover the spellings git
would index.

**Refusing every `.claude` component.** Refuses the documented `.claude/memory`
layout. Writes auto-allowed under `.claude/memory/` reach nothing Claude Code
loads; only `.claude` itself and its other directories do.

**Requiring exactly one index entry.** Refuses the unmerged gitlink a parent
merge conflict leaves, one entry per stage, just when the user opens a session
to resolve it.

**A `*..*` glob for traversal.** Rejects legitimate names such as `my..memory`
and adds nothing the component match does not already catch.

**A silent passthrough on refusal.** The shim is quiet on the common misses, but
a refusal is not a miss: the user's memory goes unredirected because of what the
checkout says, and they should learn why.

**Patching a consumer's generated `.gitlore/bin/claude`.** It drifts from the
plugin's source and leaves every other consumer exposed; the fix lives in
`scripts/install/launcher-shim` and reaches consumers through a re-install.
