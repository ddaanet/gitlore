---
description: Mount a shared gitlore memory tier into this repo, or create a new one. Activate when the user invokes /gitlore:add-tier, or asks to add, mount, join, or create a shared/org/global memory tier.
allowed-tools: ["Bash", "Read", "Write", "Edit"]
---

# gitlore:add-tier

A **tier** is a memory store shared across repos — a submodule mounted inside
this repo's `memory/` submodule. Facts that hold for every project in an org
live there instead of being duplicated per repo.

You do not run any git. You write one intent file; a hook does the git and
reports back. That is not ceremony: mounting clones, and your command sandbox
has no network.

## 1. Settle the intent

Two modes:

- **mount** — the tier remote already exists and this repo is joining it. Needs
  the tier's `name` (the directory it mounts at) and its `url`.
- **create** — no such tier exists yet; this repo stands it up. Needs a `name`
  and a `description`. Pass a `url` if the empty remote already exists;
  otherwise `gh` creates `<name>-memory` as a private repo under your account.

The `description` is the tier's **routing guidance** — the one line that tells
every future consumer what belongs in this tier and what does not. It ships on
the tier itself and is advertised at session start. Write it as a scope, not a
label: "Cross-project facts shared by all ddaanet repositories" beats "shared
memory".

Ask the user for whatever is missing. Do not guess a URL.

## 2. Write the intent file

Write `.claude/gitlore-add-tier` — `key=value`, one per line, value is the rest
of the line:

```
mode=mount
name=ddaanet
url=git@github.com:ddaanet/ddaanet-memory.git
```

```
mode=create
name=ddaanet
description=Cross-project facts shared by all ddaanet repositories
```

Activation and precedence live in one file, `memory/.gitlore-tiers`: one tier
name per line, file order is precedence (top wins), listed = active. The hook
mounts the tier **and** activates it — appending its name to the bottom of
`.gitlore-tiers` (lowest precedence, so it never outranks a tier this repo
already trusted) — as one step, then recomposes the root index within the same
batch. There is no separate manifest edit for you to make: the intent you just
wrote already names the one tier being added, so there is nothing left to
settle deliberately.

Then **stop and let the turn end**. The hook runs at the end of the batch and
its report comes back to you. Do not poll for it, and do not run
`add-tier.sh` yourself — under the sandbox it cannot reach the remote.

Read the composition report:

- **Refused** — the store is left untouched and the reason is named. Fix it,
  by hand, and re-trigger composition with any index edit.
- **Composed** — done. Do not re-read the indexes to verify; composition moves
  lines, it never rewrites them.

If the report names an `@<tier>/shared-claude.md` import line, the tier carries
conventions that must act without being looked up. Append that line, verbatim,
as the final line of this repo's `CLAUDE.md`. Then read the file it points at
and delete from `CLAUDE.md` every rule it already states — the shared file
occupies the cross-repo scope between this repo's `CLAUDE.md` and the user's own
`~/.claude/CLAUDE.md`, so repo-specific rules stay where they are.

If you want the new tier ranked somewhere other than the bottom, edit
`memory/.gitlore-tiers` yourself afterward — a plain reorder, which retriggers
composition like any other manifest edit.

## 3. Triage existing local memory against the new tier

Composing a manifest change also surfaces a triage nudge: it enumerates every
now-active tier's own scope (from its `MEMORY.md` frontmatter `description:`)
and asks you to judge each fact currently in this repo's local `memory/*.md`
against those scopes — not a fixed dichotomy, since a second or third tier can
carve up the space differently than the first one did. Route a fact up only
when an active tier's scope covers it best: `mv` the file into that tier's
directory and reprefix its root index line to `<tier>/<file>.md`. Leave a fact
no active tier covers where it is. Do not re-route a fact already inside a
tier — that reconcile is a separate, unautomated step.

## 4. Report

Tell the user the tier's name, its remote, its routing guidance, and where it
now ranks. Mention that the mount and activation are staged in `memory/`
(`.gitmodules` and `.gitlore-tiers`) and ride the next ordinary commit —
nothing else is theirs to do.
