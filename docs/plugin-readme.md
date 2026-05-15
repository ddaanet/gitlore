# gitlore

A Claude Code plugin that makes Claude's auto-memory versioned, shared, and git-backed.
See `docs/design.md` for the design and `docs/plans/` for implementation plans.

## Install (local only, Plan 01)

In your project repo, with Claude Code running:

    /gitlore:install

You'll be asked for a memory subpath (default `memory`) and your project's
pre-commit command (e.g. `lefthook run pre-commit`).

## Development

    make test       # runs the bats suite

Dependencies:
- `bash` ≥ 3.2
- `git` ≥ 2.13 (for `git submodule absorbgitdirs`; install also uses manual gitdir absorption that works on older versions)
- `jq`
- `bats-core` ≥ 1.10 (`brew install bats-core` or `npm i -g bats`)
- `mikefarah/yq` v4 OR `python3` with PyYAML — required for `wire-lefthook.sh` and `wire-overcommit.sh` to safely merge user YAML configs without clobbering existing keys. Note: yq-based wiring will strip pre-existing YAML comments from `lefthook.yml` / `.overcommit.yml` (the gitlore marker is preserved, user comments are not).

## Status

- **Plan 01 — local memory pipeline** ✅ IMPLEMENTED.
- Plans 02–05 — remote, resolve, worktrees, polish — TODO.
