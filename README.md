# gitlore

A Claude Code plugin that makes Claude's auto-memory versioned, shared, and git-backed.
See `docs/design.md` for the design, `docs/changelog.md` for how it got there, and `plans/` for implementation plans and specs.

## Install

Add the marketplace, install the plugin, then run the per-repo setup:

    /plugin marketplace add ddaanet/claude-plugins
    /plugin install gitlore@ddaanet

Then, in your project repo with Claude Code running:

    /gitlore:install

You'll be asked for a memory subpath (default `memory`) and your project's
pre-commit command (e.g. `lefthook run pre-commit`). A memory remote is created
only if the parent repo has a remote, and that step uses `gh` when available.

After `/gitlore:install`, the launcher in `.gitlore/bin/claude` is activated
automatically: direnv is approved if available, otherwise a global shim is installed
under `~/.gitlore/bin/` and install prints the one-line `PATH` addition to add to
your shell rc. Either way, Claude Code's auto-memory redirects into the submodule on
the next session.

## Development

    just test        # runs the bats suite
    just format-docs # hard-wraps prose in docs/ and plans/ (rumdl)
    just precommit   # format-docs, version drift, shellcheck, then the bats suite
    just evals      # the happy-path evals — slow, paid, drives the real CLI
    just prerelease # the release gate
    just release    # depends on prerelease; bumps, tags, publishes

Each gate records a content hash of its declared inputs on success and skips
when they are unchanged, so `just prerelease` right after a green
`just precommit` skips outright. `GITLORE_GATE_FORCE=1` runs one anyway.

The inputs are the `precommit_inputs` and `evals_inputs` variables at the top of
the `justfile`. `memory/`, `docs/` and `plans/` are in neither, so a memory-only
or prose-only commit leaves a green gate green; `docs/` and `plans/` are instead
re-wrapped by `format-docs` on every run, which is fast enough to need no
sentinel. `agents/`, `commands/` and `skills/` are in the evals set only: editing
what the plugin ships invalidates the evals, not the fast gate.

Dependencies:
- `bash` ≥ 3.2
- `git` ≥ 2.13 (for `git submodule absorbgitdirs`; install also uses manual gitdir absorption that works on older versions)
- `jq`
- `bats-core` ≥ 1.10 (`brew install bats-core` or `npm i -g bats`)
- `uv` and direnv for the dev gate: `uv sync` once materializes `.venv/bin` from `uv.lock` (rumdl for `format-docs`, PyYAML for the wiring suite) and `.envrc` puts it on `PATH`
- `mikefarah/yq` v4 OR `python3` with PyYAML — required for `wire-lefthook.sh` and `wire-overcommit.sh` to safely merge user YAML configs without clobbering existing keys. Note: yq-based wiring will strip pre-existing YAML comments from `lefthook.yml` / `.overcommit.yml` (the gitlore marker is preserved, user comments are not).

## Status

Usable and dogfooded daily on the author's own repositories. `docs/changelog.md`
records what changed and why.

## Tiers

A **tier** is a memory store shared across repos — a submodule mounted inside
this repo's memory submodule. Facts that hold for every project in an org live
there once instead of being duplicated per repo.

    /gitlore:add-tier

Mounts an existing tier, or creates one. A mounted tier is dormant until it is
listed in `memory/.gitlore-tiers` — one name per line, file order is precedence.
Listing it composes its pointer lines into the always-loaded root index.

## Writing and curating memory

Writing a fact under `memory/` triggers the `memory-writing` skill: whether
the learning deserves a memory at all, what the body says to a reader who was
not there, which tier it lands in, and whether its index line carries the
string a future session will arrive holding.

    /gitlore:index-audit

The root index is loaded verbatim into every session and Claude Code truncates
it past about 24 KB, silently. Run the audit when a session reports that only
part of `MEMORY.md` was loaded: it measures the index, walks the levers that
buy real headroom — relocate, retire, merge for routing — and dispatches two
adversarial auditors against the diff so a trim cannot quietly lose the tokens
recall depends on.

## When memory diverges

    /gitlore:resolve

Repairs a memory store or tier that has drifted from its authoritative `live`.
You rarely need to type it: memory has two gates — the pending commit against
local `live`, and local `live` against the remote — and either one, on failing,
prints a prepared-merge directive that Claude acts on by itself. A sub-agent
with fresh context synthesizes the merge, and you approve the summary before
anything is committed.

Run it yourself in the cases where nothing is left to trigger on:

- `git push` from a plain terminal — the directive went to your shell, not to a
  Claude session.
- A new or compacted session, where the directive is no longer in context.
- No divergence at all: run standalone it is a health check, and repairs a
  missing memory remote or an unpushed `live` on the spot.

The same two gates and the same command apply to every mounted tier, not just
the project's own memory.
