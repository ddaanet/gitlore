---
name: memory-writing
description: Decide whether a learning becomes a gitlore memory fact, and write the fact and its index line so a future session finds it. Use when about to create, edit, merge or retire a file under `memory/`, and when reviewing a proposed memory update. Not for the store-wide index pass — that is /gitlore:index-audit.
---

# Writing a memory

A memory states what is true, addressed to a reader who was not there: a
future session with none of this one's context, arriving at an unknown moment
for an unrelated reason. Remove the incident that produced it before saving.

## 1. Whether it should exist

Ask: **what does the next session gain that it would not otherwise have had?**
It has to benefit more than the index line it displaces. Questions 2–4 are the
three ways *otherwise* happens: another artifact already says it, the reader
gets there unaided, something recomputes it. When none fires and the answer is
still "not much", discard.

Take the questions in order and stop at the first that settles it. The verdicts
are **discard**, **relocate**, **merge**, or **save as written**. A discard
that exposes a gap in the tooling files the missing sentence where it belongs
before dropping the fact. A relocated fact leaves the store in the same change
that lands it in its owner — file and index line together.

1. **Is there an incident?** No incident, no entry — a relocation into a skill
   or CLAUDE.md included. When a rule must exist, state it positively in the
   step where it acts ("the commit lands before this file is written"), not as
   a prohibition on the agent.
2. **Does another artifact own it?** Read `<mempath>/<tier>/owned-projects.md`
   for each line of `<mempath>/.gitlore-tiers`, where `<mempath>` is
   `git config --file .gitmodules submodule.gitlore-memory.path` run from the repo
   root, skipping a tier without the file. Move the fact to its owner even when
   the memory is accurate, and grep the owner for the load-bearing terms before
   accepting that it covers the fact:
   - **A skill:** the fact reduces to "when using \<skill\>, do X". Check which way
     the claim points before counting the skill as its owner: a fact written to
     override an installed skill sits on that skill's topic, so a coverage scan
     flags it as owned. Then delete the fact; if the skill lacks X, fix the skill
     when this repo owns it, otherwise route the fact as the inventory says.
   - **A design doc:** a decision, a supersession, a dated status. Record it in the
     living design doc.
   - **The code:** how one call site must behave. Write it as a comment at that
     site.
   - **CLAUDE.md or a shared tier's conventions file:** a convention binding all
     work in one repo or tier. A fact meant to be found on meeting a symptom stays
     in memory.
   - **A hook or tool that prints the diagnosis when it fires:** delete a memory
     that restates its output; when the output lacks it, fix the output when this
     repo owns it, otherwise route the fact as the inventory says.
   - **A sibling project's skill body, agent definition, hook or tool output:** route
     the fact as the inventory says.
3. **Would the reader reach it unaided?** Discard a fact restating common
   sense, or following in one step from an indexed memory. The tell: the body's
   general claim is unarguable and only its instance is interesting. Discard it,
   unless a reader meeting that instance again would not reach it unaided; then
   cut the general claim and keep the instance.
4. **Who reconstructs it?** A script or the harness recomputing it: drop and
   defer. A model inferring it from a paraphrase, with the failure silent:
   carry it.
5. **What moment does it fire at?** State the moment in one clause. The same
   clause as a file already in the store means a section in that file (§3).
   Prefer a *literal* — a string a tool result surfaces. An activity ("writing a
   design doc") goes to the skill owning it (Q2); with no such skill it stays as a
   HOW line (§7) whose condition names the task. A symptom with no string needs a
   checkpoint inside a skill that owns the surrounding moment.
6. **Which tier?** Mechanism scoped to this repo, or to the class of repo (§5).
7. **Does the body survive the strip?** Incident out, first person out,
   deictics out, present tense in, an ageing observation version-stamped (§2).
8. **Does the index line route to it?** The distinctive literal a session would
   arrive holding has to be in the line (§7).

Ask "what is the new learning?" and keep only the answer. What stays in memory
is what no owner can carry: a correction from the user, a failure mode observed
in this repo, a constraint from outside the artifact's world. If nothing
survives, write nothing — an empty flush is the normal case.

## 2. What the body says

Write from the reader's vantage, in the present tense. Lead with the rule; give
the reasoning that makes it decidable in a new situation; cut every sentence
that is narration. Never write:

- *What used to be or what just changed*, or a snapshot of which repos have
  migrated or which version is current.
- *The author's present* — "I did X and was corrected".
- *Pending or temporal framing* — work that "needs a fresh session".
- *Deictics* — *now*, *here*, *today*, *currently*, *recently*, *this session*.
  Name the condition instead, and version-stamp an observation that could age
  (`CC 2.1.220`).
- *Volatile git state* — commit ids, branch tips, "uncommitted as of" notes;
  identify things by durable names.

A quoted correction may name its source. Rename `user` only where the referent
is the person who ran, said or corrected something; elsewhere it is a term of
art (a user-visible hook channel, `protocol.file.allow=user`).

## 3. A new file, or a section in one that exists

Open [file-shape.md](references/file-shape.md) when a file with the same moment
clause already exists.

## 4. Organising a file that holds many facts

Open [file-shape.md](references/file-shape.md) before adding to an existing
file.

## 5. Which tier

Open [tier-routing.md](references/tier-routing.md) when a tier is mounted and the
fact might go up.

## 6. Links when a fact routes up

Open [tier-routing.md](references/tier-routing.md) when a fact routes up to a tier.

## 7. The index line

An index line lets an agent decide read-or-skip, usually on a string met
**mid-task**: a git error, a flag, a filename, a symptom in a tool result. Edit
the line, never the file's `description:` frontmatter, which is synced from it.

Every line is one of three kinds:

- **WHEN** — fires on a symptom met mid-task. The identifiers *are* the
  trigger; the prescription is payload.
- **HOW** — fires on a task or decision being started. The condition is the
  trigger, and it often hides inside what reads like prescription.
- **Acted-inline** — no lookup step: what model to name, how to answer a
  correction. Put these in CLAUDE.md or the tier's conventions file, not the
  index, carried across **whole, with their carve-outs**.

Carry the symptom, not the diagnosis: the observable a session arrives holding
— the error substring, the flag, the misbehaviour. Keep quoted error strings,
config keys, env vars, flag and event names, file paths, and any contrast whose
value was the disambiguation (`fetch -q` vs `push -q`). Cut rationale, dates,
provenance, cross-references, a hook that restates its own title, and a hook
naming a count rather than a thing.

Write the triggers the fact needs even when the index is over the byte cap;
take the overage to `/gitlore:index-audit` separately.

## 8. Landing it

Write the file under `memory/` (or the matching tier's directory) and add its
line to the root `memory/MEMORY.md` — `- [Title](<tier>/<file>.md) — hook`;
tier carriers and frontmatter follow from that edit. The fact is committed with the
user's approved summary through `gitlore-commit` (the `gitlore:commit` skill), and its pointer rides
the parent commit carrying the change it documents.

## 9. Arriving here at a gate, over facts already written

Open [gate-pass.md](references/gate-pass.md) when a caller sends you here over facts
already written: the `gitlore:commit` review (before the approval summary),
`/gitlore:install`, or a tier mount.
