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

After `/gitlore:install`, the launcher in `.gitlore/bin/claude` is activated
automatically: direnv is approved if available, otherwise a global shim is installed
under `~/.gitlore/bin/` and install prints the one-line `PATH` addition to add to
your shell rc. Either way, Claude Code's auto-memory redirects into the submodule on
the next session.

## Development

    just test       # runs the bats suite
    just precommit  # version drift, shellcheck, then the bats suite
    just evals      # the happy-path evals — slow, paid, drives the real CLI
    just prerelease # the release gate
    just release    # depends on prerelease; bumps, tags, publishes

Each gate records a content hash of its declared inputs on success and skips
when they are unchanged, so `just prerelease` right after a green
`just precommit` skips outright. `GITLORE_GATE_FORCE=1` runs one anyway.

The inputs are the `precommit_inputs` and `evals_inputs` variables at the top of
the `justfile`. `memory/` and `docs/` are in neither, so a memory-only or
docs-only commit leaves a green gate green. `agents/`, `commands/` and `skills/`
are in the evals set only: editing what the plugin ships invalidates the evals,
not the fast gate.

Dependencies:
- `bash` ≥ 3.2
- `git` ≥ 2.13 (for `git submodule absorbgitdirs`; install also uses manual gitdir absorption that works on older versions)
- `jq`
- `bats-core` ≥ 1.10 (`brew install bats-core` or `npm i -g bats`)
- `mikefarah/yq` v4 OR `python3` with PyYAML — required for `wire-lefthook.sh` and `wire-overcommit.sh` to safely merge user YAML configs without clobbering existing keys. Note: yq-based wiring will strip pre-existing YAML comments from `lefthook.yml` / `.overcommit.yml` (the gitlore marker is preserved, user comments are not).

## Status

Feature-complete: every functional requirement and design decision in
`docs/design.md` (FR1–FR16, D1–D18) is implemented and tested.

- **Plan 01 — local memory pipeline** ✅
- **Plan 02 — remote and push** ✅
- **Plan 03 — semantic merge / resolve** ✅
- **Plan 04 — marketplace install** ✅ (push + marketplace entry + outer-loop dogfood)
- **Plan 05 — memory redirect launcher** ✅ (shim + Placement A direnv + Placement B global + SessionStart guard)
- **Plan 07 — gitlink-aware wrappers / worktree lifecycle (D11)** ✅ (common-dir-anchored hook wrappers; SessionStart creates the memory worktree in linked worktrees; advisory `WorktreeRemove` teardown)
- **Dogfood-driven hardening (D12–D16)** ✅ (submodule-side commit gate; git lock-contention retry; SessionStart output on `systemMessage`; in-process-worktree memory-drift guard; standalone memory-commit entry point; SessionStart disclosure trimmed to prohibition + seamless happy path)
- **FR11 memory-commit batch** ✅ (a `PostToolBatch` file-trigger hook commits memory from an agent-written message, sidestepping the sandbox and commit-approval classifier — no Stop hook)
- **D17 — tiered memory (FR15)** ✅ index→frontmatter sync, nested tier submodules discovered by enclosure, detach-at-`live` propagation, commit/push lockstep, index composition, and `/gitlore:add-tier`. One merge policy applies at every level: memory and each tier get the same two gates and the same `/gitlore:resolve`
- **D18 — active recall (FR16)** ✅ the agent names memory files in `.claude/gitlore-recall` and a `PostToolBatch` hook injects their bodies, so a fact whose trigger only appears mid-task can still reach context
- **Index authority** ✅ the always-loaded index one-liner is canonical for a pointer line's text *and* its presence, enforced non-destructively — removing a line never deletes the file, and a bullet whose file is missing is reported rather than repaired by deletion
- **Routing-key advisories** ✅ the index→frontmatter sync reports, without ever refusing a write, when the index outgrows its byte budget and when a `reference` or `project` line carries no literal trigger token

## Tiers

A **tier** is a memory store shared across repos — a submodule mounted inside
this repo's memory submodule. Facts that hold for every project in an org live
there once instead of being duplicated per repo.

    /gitlore:add-tier

Mounts an existing tier, or creates one. A mounted tier is dormant until it is
listed in `memory/.gitlore-tiers` — one name per line, file order is precedence.
Listing it composes its pointer lines into the always-loaded root index.

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
