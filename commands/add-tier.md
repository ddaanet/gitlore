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

Then **stop and let the turn end**. The hook runs at the end of the batch and
its report comes back to you. Do not poll for it, and do not run `add-tier.sh`
yourself — under the sandbox it cannot reach the remote.

The intent file is consumed either way. If the report is a failure, fix the
cause and write a corrected intent file.

## 3. Activate it

A mounted tier is **inactive** until it is listed. Activation and precedence are
one deliberate file, `memory/.gitlore-tiers`: one tier name per line, file order
is precedence (top wins), listed = active.

Append the tier's name (or insert it where the user wants it ranked). That edit
retriggers composition, which splices the tier's pointer lines into the root
`memory/MEMORY.md` ahead of the project's own. Read the composition report:

- **Refused** — the store is left untouched and the reason is named. Fix it and
  edit the manifest again.
- **Composed** — done. Do not re-read the indexes to verify; composition moves
  lines, it never rewrites them.

## 4. Report

Tell the user the tier's name, its remote, its routing guidance, and where it
now ranks. Mention that the mount is staged in `memory/.gitmodules` and rides
the next ordinary commit — nothing else is theirs to do.
