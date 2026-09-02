## Brief: add a "how does this benefit further sessions?" test to memory-writing

2026-09-02

Written from edify, where two facts were drafted, held against `memory-writing`
§1, judged worth saving, and then rejected the moment my human partner asked
"how do those benefit further sessions?". §1's existing questions did not catch
either one. The gap is reproducible, so the skill should carry the question.

### Decisions

- Add the benefit question to §1 as its own numbered step, ahead of the tier and
  body questions. It is a stronger filter than the ones around it: it asks what
  the next session *gains that it would not otherwise have had*, which subsumes
  several ownership cases without enumerating owners.
- Extend §1 question 2's list of owners with
  **a hook or tool that prints the diagnosis when it fires**. The current owners
  are a skill, a design doc, the code, and CLAUDE.md — all authored artifacts a
  reader must go and consult. Runtime output is a different kind of owner and a
  better teacher: it arrives with the line number, at the moment of the failure,
  without costing index bytes on every unrelated session.
- State the bar as comparative, not absolute. The index is capped, so "a future
  session would benefit" is not the test; "would benefit more than the line this
  displaces" is. §7 already says an over-cap index is a retirement decision —
  this is the same economy applied at write time.
- When a fact fails the test, say where the residue goes. Both rejected facts
  had a genuine one-sentence gap in the tooling, and dropping the memory without
  filing that sentence loses it. The verdict list in §1 should carry
  **relocate-upstream** as distinct from *discard*.

### Constraints

- The skill ships to consumers who do not have this store, so nothing added may
  cite a memory file by name — inline the criteria, per the store's own rule
  that distributed text never cites memory files.
- §1 is a stop-at-the-first-that-settles-it ladder. A new step has to be placed
  where it settles cases the earlier ones let through, not appended as a
  reminder after the verdict is already taken.
- The skill's `description:` is injected every session in every mounting repo,
  so length added to the body is cheap and length added to the description is
  not. This change is body-only.

### Rejected approaches

- Folding it into question 3 ("would the reader reach it unaided?"). That
  question is about common sense and one-step inference from an indexed memory.
  It does not reach a fact the *tooling* will re-teach, which is why it passed
  both rejected facts.
- Folding it into question 4 ("who reconstructs it?"). Closest existing
  question, but it is scoped to a script or the harness *recomputing a value*. A
  hook printing a diagnosis is not recomputation, and reading question 4 that
  broadly is a stretch a first-time reader will not make.
- Leaving it to the commit gate. The gate already demands the skill be invoked
  before drafting the summary, and that is exactly what happened here — the
  facts survived it. The question has to be in the ladder, not in the wrapper.

### Additional context

The two worked examples, both from edify on 2026-09-02, both written and then
deleted before commit:

1. **Composition only recognizes a plain link-first pointer bullet.** A bolded
   link, a `##` heading or a `- **Key:** value` bullet refuses the whole compose
   when interleaved. The tier-composition hook already prints
   `interleaved non-bullet line N inside the pointer block` plus the remedy, and
   a second hook prints that a hook containing its own markdown link welds two
   pointer bullets onto one line and must be split. A future session is taught
   this by the hook, later and better than by an index line.

   Genuine residue, currently unsignalled anywhere: a non-pointer line placed
   *ahead* of the pointer block composes cleanly and routes nothing, and a
   `grep '^- \['` byte count does not include it — so the index reads smaller
   than the file the loader truncates. Belongs in the `/gitlore:index-audit`
   skill: measure the whole file, not the pointer lines.

2. **A prepared merge lands on its continuation script, not on the merger
   agent's report.** `gitlore:memory-merger` can return a correct synthesis —
   conflicts resolved, files staged, tree clean — with `MERGE_HEAD` still set.
   `/gitlore:merge` step 2 already says to re-run the reconcile command, and
   following it produces the right behaviour, so the memory reduced to "do what
   step 2 says".

   Genuine residue: step 2 explains a repeat as
   *another store may still be behind*. It does not say that the **same** store
   returning the **same** `memory merge prepared` block means the merge is
   unlanded rather than newly diverged. One sentence in step 2.

Both residues are skill edits in this repo, and are worth making whether or not
the §1 change lands.
