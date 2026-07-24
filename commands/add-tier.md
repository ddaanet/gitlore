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

## 2. Write the intent file, and usually the manifest line too

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

A mounted tier is **inactive** until it is listed. Activation and precedence
are one deliberate file, `memory/.gitlore-tiers`: one tier name per line, file
order is precedence (top wins), listed = active.

**Default to mounting and activating in the same turn**: write the intent file
above *and* append the tier's name to `memory/.gitlore-tiers` (or insert it
where the user wants it ranked) before the turn ends. The hook chain mounts
the tier and composes its pointer lines into the root index within the same
batch — one turn gets you a usable tier. Write the intent alone only when the
tier should stay **dormant** (mounted but not yet listed); add the manifest
line in a later turn to activate it.

Then **stop and let the turn end**. The hooks run at the end of the batch and
their reports come back to you. Do not poll for them, and do not run
`add-tier.sh` yourself — under the sandbox it cannot reach the remote.

The intent file is consumed either way. If the mount report is a failure, a
manifest line written in the same turn is left pointing at an absent module —
composition will refuse and say so; that stray line is inert and costs
nothing. Fix the intent's cause and write it again; the retry heals both.

Read the composition report:

- **Refused** — the store is left untouched and the reason is named. Fix it and
  edit the manifest again.
- **Composed** — done. Do not re-read the indexes to verify; composition moves
  lines, it never rewrites them.

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
now ranks (or that it was left dormant). Mention that the mount is staged in
`memory/.gitmodules` and rides the next ordinary commit — nothing else is
theirs to do.
