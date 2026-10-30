---
name: commit
description: Commit pending gitlore memory changes. Invoke it first, before any summary is drafted, whenever memory files were written or edited and are not yet committed, or when the user asks to commit memory; it gives the summary format and commits once the user approves the shown summary. Not for publishing memory to its remote — that is gitlore:push.
allowed-tools: ["Bash", "Skill"]
---

# gitlore:commit

You are committing pending memory changes. A memory commit is an act the user
approves, so the summary is shown first and committed only after the user's
reply approves it.

## Review directive

Before drafting the summary, invoke the `gitlore:memory-writing` skill and hold
every pending memory change against it: whether the fact belongs in the store at
all, what its body claims, which tier it sits in, and whether its index line
carries the literal a future session arrives holding. Land those fixes first —
the summary describes the facts as they will be committed.

## Summary format

The summary is one section per store with changes, and nothing outside them.
Each section is headed by the store it covers:

- `== <tier> ==` for each mounted tier store that changed, where `<tier>` is the
  tier's mount name, its directory under `memory/`.
- `== memory ==` for the root memory store.

Use these headers always, whether one store changed or several. Tiers come
before `memory`. Each section is that store's whole commit message: a subject
line with no conventional-commit prefix, a blank line, then one paragraph per
changed memory file in that store.

A paragraph opens with a bold prefix naming the file's kind — New, Update,
Augment, Reduce, or Remove — and its slug, names the change in one clause, and
spends the rest on what the diff cannot show: what prompted it (the incident,
correction or measurement, with its date or version), what the old wording got
wrong, and for a Reduce or Remove where the content went. Do not retell the new
body or the index line: the edits are already in the conversation and in
`git show`, and a retelling buries the cause the approver is weighing. Attribute
a decision or correction to whoever made it.

A `MEMORY.md` — root or tier — gets no paragraph. Root changes that only carry
a tier's facts — its index lines in the root `MEMORY.md`, its gitlink — take no
`== memory ==` section; they are committed with the tier's.

Template, with a tier store and a root change:

```text
== <tier> ==

<subject line for the tier commit>

**New <tier>/<slug>:** what it records, in one clause. What prompted
writing it now.

**Update <tier>/<slug>:** what changed, in one clause. What the old wording
got wrong, and the evidence that showed it.

== memory ==

<subject line for the root commit>

**Remove <slug>:** what showed it wrong or redundant, and where its
content now lives.
```

## Protocol

1. Show the drafted summary to the user as plain text, and end the turn.
   Do not run any commit command in the same turn as the draft.
2. A request to commit memory is not approval of a summary the user has not
   seen. Only the user's reply to the shown summary approves it.
3. On an approving reply, run from the repo root, with the approved text
   verbatim on stdin through a quoted heredoc so the shell expands nothing:

```bash
gitlore-commit <<'EOF'
<approved summary, verbatim>
EOF
```

4. Relay the command's output. If it exits non-zero, surface the output
   verbatim and stop; do not retry with altered text.
5. If the user asks for changes, redraft the summary, show it again, and end
   the turn. Each redraft needs its own approval.
