# Brief: migrate scripts and tests from bash to Python

Decisions my human partner took on 2026-11-18, recorded here while the 0.13
release ritual runs; the design doc takes them when the migration starts.
Nothing in this file is started.

## Why

Scripts are 83 files and about 12k lines of bash; tests are 189 files and about
36k lines of bats. The defects the last releases spent commits on are bash
classes: `set -e` blind spots, `LC_ALL=C` at every call that matches git's text,
`while IFS= read -r -d ''`, `|| [ -n "$line" ]`, process groups under `set -m`
for a bounded fetch, and the bash 3.2 and BSD divergences the `bsd-stubs` helper
exists to catch. Python removes the class, not the line count: 864 `git` calls
become `subprocess.run` with an explicit check, and the bounded fetch becomes
`timeout=`.

Rust was weighed and dropped: a plugin pulled from a dist branch has no binary
channel, and the workload is git orchestration at human timescales.

## Runtime (decided)

- **`uv` is a requirement**, stated in `README.md` beside git. Python itself is
  not a prerequisite of the user's machine: `uv` installs the interpreter.
- **Python 3.15 floor**, for lazy imports (PEP 810), which keep hook startup
  cheap without hand-rolled import deferral.
- **The plugin builds its own `.venv` in the plugin cache**
  (`${CLAUDE_PLUGIN_ROOT}/.venv`), with `uv sync`, and every shipped entry point
  runs `${CLAUDE_PLUGIN_ROOT}/.venv/bin/python`. `uv` runs only at venv build
  time; nothing invokes `uv run` from an agent's Bash call
  (`memory/ddaanet/uv-direnv-venv.md` holds why).
- **Frequent hooks keep a bash shim** that takes the cheap exits (an ignored
  tool, a missing memory dir) in bash and execs Python for the rest;
  `gitlore_emit_hook_wrapper` is already that shape.

## Layout (default, open)

Follow the sibling pattern (`edify/pyproject.toml`): a `pyproject.toml` that is
dev tooling plus runtime pins, `[tool.uv] package = false`, entry points under
`bin/` with no `.py` extension that `sys.path.insert` a sibling `lib/` (edify's
`bin/edify-markdown` does this), ruff with `extend-include` for the
extensionless entry points and `select = ["ALL"]` with edify's ignore list,
mypy, pytest. `requires-python = ">=3.15"` holds both the tools and the shipped
code, so no `per-file-target-version` split.

## Sequencing (validated)

Tests first, module by module, against the bash implementation: a pytest port is
done when it is green against the existing scripts, which proves it checks what
the bats suite checked. Then the module is ported under those tests. Start with
a leaf with a thick suite and portability scars: the bounded fetch and the
session-start line. The bats suite for a module is deleted in the same commit
that lands its Python port, never earlier.

## Open points, each with a default

1. **Where the venv is built.** Default: the SessionStart hook, when `.venv` is
   absent or `uv.lock` is newer than it. Hooks run outside the command sandbox,
   which denies writes under `~/.claude/plugins` and to `~/.cache/uv`, so an
   agent's Bash call cannot build it; `gitlore:install` can also run it for a
   fresh install.
2. **What ships.** Default: `pyproject.toml` and `uv.lock` join `dist.include`,
   since `uv sync` in the cache needs both; `.venv` is gitignored and never in
   dist.
3. **Package or `lib/`.** Default: `lib/` with `package = false`, as above. The
   alternative, a `src/gitlore/` package installed editable by `uv sync`, gives
   `python -m gitlore` and clean imports at the cost of a build backend; it is
   the right move if more than a handful of modules import each other.

Settled 2026-11-18: third-party runtime dependencies are allowed in shipped
code; the cached `.venv` built by `uv sync` is what makes them cheap, and
standard-library-only is not a requirement.
