# gitlore

A Claude Code plugin that makes Claude's auto-memory versioned, shared, and git-backed.

## Install

Add the marketplace, install the plugin, then run the per-repo setup:

    /plugin marketplace add ddaanet/claude-plugins
    /plugin install gitlore@ddaanet

Then, in your project repo with Claude Code running:

    /gitlore:install

You'll be asked for a memory subpath (default `memory`). A memory remote is
created only if the parent repo has a remote, and that step uses `gh` when
available.

After `/gitlore:install`, the launcher in `.gitlore/bin/claude` is activated
automatically: direnv is approved if available, otherwise a global shim is installed
under `~/.gitlore/bin/` and install prints the one-line `PATH` addition to add to
your shell rc. Either way, Claude Code's auto-memory redirects into the submodule on
the next session.

## Requirements

- `bash` ≥ 3.2 for the shipped scripts.
- `git` ≥ 2.13 (for `git submodule absorbgitdirs`; install also uses manual gitdir absorption that works on older versions)
- `jq`
- `mikefarah/yq` v4 OR `python3` with PyYAML — required for `wire-lefthook.sh` and `wire-overcommit.sh` to safely merge user YAML configs without clobbering existing keys. Note: yq-based wiring will strip pre-existing YAML comments from `lefthook.yml` / `.overcommit.yml` (the gitlore marker is preserved, user comments are not).

## Development

The [design document](https://github.com/ddaanet/gitlore/blob/main/docs/design.md)
and its nodes hold the design, including the test suite and the commit gate
for working on gitlore itself.

## Status

Usable and dogfooded daily on the author's own repositories.

## Tiers

A **tier** is a memory store shared across repos — a submodule mounted inside
this repo's memory submodule. Facts that hold for every project in an org live
there once instead of being duplicated per repo.

    /gitlore:add-tier

Mounts an existing tier, or creates one. A mounted tier is dormant until it is
listed in `memory/.gitlore-tiers` — one name per line, file order is precedence.
Listing it composes its pointer lines into the always-loaded root index.

## Publishing and taking

    /gitlore:push

Publishes committed memory and every mounted tier to their own remotes, with no
parent push. Memory `live` advances locally on every memory commit but reaches
its remote only when a `git push` of the parent runs the pre-push hook, so a
session that commits memory and then ends leaves those facts in the local clone
alone. There is no approval step: the commit gate already approved this content.

    /gitlore:merge

The other half — takes what each mounted tier's remote holds, then what memory's
own does, and publishes nothing of this repo's. A tier stays at the commit the
memory tree records for it and nothing advances it on its own, so facts another
repo published sit on the tier's remote until this runs. Either command hands a
divergence to `/gitlore:resolve` and resumes once the merge has landed.

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

## Recalling a fact mid-task

    /gitlore:recall

The root index loads into every session; the facts it points at do not. Recall
fetches specific bodies into context on demand, from a trigger the prompt never
carried — an error string in a tool result, a flag in a file just read. Claude
selects from the index it already holds and reads the bodies itself, in one
batch. It is a skill, so it fires on such a trigger without being asked; typing
the command is for when you want a topic looked up directly.

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
