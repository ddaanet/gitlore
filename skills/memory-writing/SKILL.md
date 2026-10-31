---
name: memory-writing
description: Decide whether a learning becomes a gitlore memory fact, and write the fact and its index line so a future session finds it. Use when about to create, edit, merge or retire a file under `memory/`, and when reviewing a proposed memory update. Not for the store-wide index pass — that is /gitlore:index-audit.
---

# Writing a memory

A memory states what is true, addressed to a reader who was not there: a
future session with none of this one's context, arriving at an unknown moment
for an unrelated reason. The incident that produced it is scaffolding — useful
while writing, removed before saving.

## 1. Whether it should exist

One question sits over the rest: **what does the next session gain that it
would not otherwise have had?** The bar is comparative, not absolute — the
index is capped, so "a future session would benefit" is not the test; it has to
benefit more than the line it displaces. Questions 2–4 are the three ways
*otherwise* happens: another artifact already says it, the reader gets there
unaided, something recomputes it. When none of the three fires and the answer
is still "not much", that settles it on its own — discard.

Take the questions in order and stop at the first that settles it. The verdicts
are **discard**, **relocate**, **merge**, or **save as written**. A discard
that leaves a real gap in the tooling files the missing sentence where it
belongs before dropping the fact: the fact was wrong as a memory, but the gap
it exposed is real and nothing else records it. A relocated fact leaves the
store in the same change that lands it in its owner — file and index line
together. A copy held until the owner ships is a second home with a deadline
nobody tracks.

1. **Is there an incident?** No incident, no entry. A rule or anti-pattern for
   a failure nobody has seen dilutes the real entries and costs context on every
   load. That holds equally for the skill or CLAUDE.md a fact is relocated into.
   When a rule must exist, state it positively in the step where it acts ("the
   commit lands before this file is written") rather than as a prohibition on
   the agent — a positive ordering constrains sequence without forbidding the
   action, and the request that reaches a decision point is often the one that
   wants the "forbidden" thing.
2. **Does another artifact own it?** A memory repeating what another artifact
   owns is in the wrong place: the owner states it at the moment it matters,
   while the copy drifts and pays index bytes every session to say it worse.
   Accuracy is not the test — an accurate fact in the wrong home is still a
   category error. The owners:
   Open [owners.md](references/owners.md) once a candidate owner is in view: the
   list of owners and how to read the inventory.
   Grep the owner for the load-bearing terms before accepting a pointer that
   claims coverage.
3. **Would the reader reach it unaided?** A fact restating common sense, or one
   that follows in one step from a memory already indexed, spends index bytes
   telling a competent reader what it had. The tell: the body's general claim is
   unarguable and only its instance is interesting — the instance was the whole
   content, and the instance does not generalise.
4. **Who reconstructs it?** A script or the harness recomputing it: drop and
   defer. A model inferring it from a paraphrase, with the failure silent:
   carry it.
5. **What moment does it fire at?** State the moment in one clause. The same
   clause as a file already in the store means a section in that file, not a
   new one (§3). Then check the clause names a *literal*, not an activity: an
   index line fires when a tool result surfaces a string, so a fact whose
   moment is "writing a design doc" or "authoring a hook" has nothing to match
   on and is never read, however well written. That content belongs to the
   skill owning the activity (Q2), or needs a symptom-shaped hook it does not
   yet have. The hardest case is a symptom with no string — nothing errors, the
   change simply appears not to work — which neither route reaches: it needs a
   checkpoint inside a skill that owns the surrounding moment.
6. **Which tier?** Mechanism scoped to this repo, or to the class of repo (§5).
7. **Does the body survive the strip?** Incident out, first person out,
   deictics out, present tense in, an ageing observation version-stamped (§2).
8. **Does the index line route to it?** The distinctive literal a session would
   arrive holding has to be in the line (§7).

Ask "what is the new learning?" and keep only the answer. What legitimately
stays in memory is what no owner can carry: a correction from the user, a
failure mode observed in this repo, a constraint from outside the artifact's
world. If nothing survives, there was no memory to write — an empty flush is
the normal case.

## 2. What the body says

Write from the reader's vantage. The body states what *is*, never what used to
be or what just changed — a fact phrased as a delta is unreadable once the
before-state is gone. Lead with the rule in the present tense; give the
reasoning that makes it decidable in a new situation; cut every sentence that is
narration rather than instruction. Five habits make a memory worse than useless:

- *Describing what used to be.* A snapshot of which repos have migrated or
  which version is current becomes false without warning and gets acted on.
- *Writing from the author's present.* "I did X and was corrected" — the reader
  has no session, no I, and no way to tell whether the anecdote generalises.
- *Pending or temporal framing.* Work that "needs a fresh session" reads as
  outstanding forever and invites redoing finished work.
- *Deictics.* *now*, *here*, *today*, *currently*, *recently*, *this session*
  are anchored to a moment the reader is not in. Name the condition instead of
  the moment, and version-stamp an observation that could age (`CC 2.1.220`)
  rather than calling it recent.
- *Volatile git state.* No commit ids, branch tips or "uncommitted as of"
  notes; identify things by durable names.

A quoted correction may name its source: an attribution credits evidence.
Distinguish the person from the role — `user` is a term of art in most
described systems (a user-visible hook channel, `protocol.file.allow=user`);
rename only where the referent is the person who ran, said or corrected
something.

## 3. A new file, or a section in one that exists

Open [file-shape.md](references/file-shape.md) when a file with the same moment
clause already exists.

## 4. Organising a file that holds many facts

Open [file-shape.md](references/file-shape.md) when a file is filling toward
recall's 4096-byte limit.

## 5. Which tier

Open [tier-routing.md](references/tier-routing.md) when a tier is mounted and the
fact might go up.

## 6. Links when a fact routes up

Open [tier-routing.md](references/tier-routing.md) when a fact routes up to a tier.

## 7. The index line

An index line's only job is to let an agent decide read-or-skip, usually on a
string met **mid-task**: a git error, a flag, a filename, a symptom in a tool
result. The line is canonical — the file's `description:` is synced from it, so
edit the line, never the frontmatter.

Every line is one of three kinds:

- **WHEN** — fires on a symptom met mid-task. The identifiers *are* the
  trigger; the prescription is payload.
- **HOW** — fires on a task or decision being started. The condition is the
  trigger, and it often hides inside what reads like prescription.
- **Acted-inline** — there is no lookup step: what model to name, how to answer
  a correction. These do not belong in the index at all. They belong in
  CLAUDE.md or the tier's conventions file, carried across **whole, with their
  carve-outs** — the "how to apply" section is where the exceptions live, and a
  rule that lost its exception is not shorter, it is wrong, in always-on context
  where nothing routes to the file that would correct it.

Carry the symptom, not the diagnosis. A line that lists what each case is
*called* is legible only after the file has been read; what a session arrives
holding is the observable — the error substring, the flag, the misbehaviour.
Keep quoted error strings, config keys, env vars, flag and event names, file
paths, and any contrast whose value was the disambiguation (`fetch -q` vs
`push -q`). Cut rationale, dates, provenance, cross-references, a hook that
restates its own title, and a hook naming a count rather than a thing.
Trimming naturally preserves prescriptions and cuts symptoms, because that is
what reads well as prose — exactly backwards for a routing table.

Being over the byte cap is never a reason to under-trigger a new or updated
fact. A line that omits the literal a recall pass would match on is already
lost, silently, with the file still there looking complete. Write the triggers
the fact needs; an index over the cap is the retirement decision coming due,
taken separately with `/gitlore:index-audit`.

Open [owners.md](references/owners.md) when a fact is written to override an
installed skill.

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
