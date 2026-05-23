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

> **Known limitation (pending the next plan):** the per-project memory redirect
> requires the launch-time launcher described in `docs/design.md` (D10) — Claude
> Code ignores `autoMemoryDirectory` in project settings. Until the launcher
> ships, memory still writes to Claude Code's default directory rather than the
> submodule.

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
- **Plan 05 — memory redirect launcher** 📋 designed (D10), not yet implemented.
