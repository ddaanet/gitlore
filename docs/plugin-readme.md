# gitlore

A Claude Code plugin that makes Claude's auto-memory versioned, shared, and git-backed.
See `docs/design.md` for the design and `docs/plans/` for implementation plans.

## Install

Add the marketplace, install the plugin, then run the per-repo setup:

    /plugin marketplace add ddaanet/claude-plugins
    /plugin install gitlore@ddaanet

Then, in your project repo with Claude Code running:

    /gitlore:install

You'll be asked for a memory subpath (default `memory`) and your project's
pre-commit command (e.g. `lefthook run pre-commit`). A memory remote is created
only if the parent repo has a remote, and that step uses `gh` when available.

After `/gitlore:install`, run `direnv allow` so the launcher in `.gitlore/bin/claude`
takes over and CC's native auto-memory redirects into the submodule. If you don't
use direnv (or you launch Claude Code from outside an allowed directory), run
`/gitlore:install-launcher` instead — it installs the launcher globally and prints
the one-line `PATH` change to add to your shell rc.

## Development

    make test       # runs the bats suite

Dependencies:
- `bash` ≥ 3.2
- `git` ≥ 2.13 (for `git submodule absorbgitdirs`; install also uses manual gitdir absorption that works on older versions)
- `jq`
- `bats-core` ≥ 1.10 (`brew install bats-core` or `npm i -g bats`)
- `mikefarah/yq` v4 OR `python3` with PyYAML — required for `wire-lefthook.sh` and `wire-overcommit.sh` to safely merge user YAML configs without clobbering existing keys. Note: yq-based wiring will strip pre-existing YAML comments from `lefthook.yml` / `.overcommit.yml` (the gitlore marker is preserved, user comments are not).

## Status

- **Plan 01 — local memory pipeline** ✅
- **Plan 02 — remote and push** ✅
- **Plan 03 — semantic merge / resolve** ✅
- **Plan 04 — marketplace install** 🚧 (push + marketplace entry done; outer-loop dogfood pending)
- **Plan 05 — memory redirect launcher** ✅ (shim + Placement A direnv + Placement B global + SessionStart guard; dogfood pending)
