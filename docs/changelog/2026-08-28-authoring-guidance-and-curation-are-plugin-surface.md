# 2026-08-28 — Authoring guidance and index curation ship as plugin surface, not memories (D47)

A review pass over the shared `ddaanet` tier, ordered by index-line size,
opened on its two largest lines: `memory-writing`, the rules for what a fact
says and whether it should exist, and `index-compaction-triggers`, the rules
for what an index line carries and how a store-wide trim goes wrong. Together
they were 32 KB of body and 1,459 B of a capped index, and the first file's own
ownership rule condemned both — a body that reduces to "when writing a memory,
do X" belongs to whatever fires at that moment, and gitlore, which ships
`merge`, `push`, `recall` and `resolve`, owned nothing that fires at authoring
or curation.

The first proposal was a re-split of the curation fact along its two moments,
every-write versus curation-pass, since a merged index line could not be both
a HOW and a WHEN kind at once. Off the index that constraint disappears and the
asymmetry argues for progressive disclosure instead: the every-write half — an
index line's only job, the WHEN/HOW/acted-inline classification, symptom over
diagnosis, never under-trigger — joined the writing rules in
`skills/memory-writing/SKILL.md`, and the pass itself — the two budgets and
the loader cap, the before-and-after vocabulary sweep, the two adversarial
auditor briefs, the whole-submodule frontmatter review — became
`commands/index-audit.md`. The five file-organisation rules that came out of
restructuring `sandbox-effects` in the same pass, and the no-incident-no-entry
test that had been its own fact, landed in the skill rather than in memory.

Two things were decided against: a `PreToolUse` deny on writes under
`memory/` to reach the pre-write moment, which costs a turn on every session
that writes memory when the skill description already reaches it; and an
index-size trigger, which fires on a condition that can be permanently true
and before the task begins. Whether constrained generation or
unconstrained-then-review produces better facts is left open for `just evals`.
The condensation cut evidence and provenance rather than relocating it: the
measurements that make a counterintuitive rule survive disagreement stay
inline as figures, and the incidents behind them — the 2026-08-01 relocation
pass that took 24 acted-inline lines out and grew the shared conventions file
by 8 KB, the 32,405 → 24,316 B trim whose 58 audit findings consumed the
headroom it bought, the six tmux facts retired while two skills still built on
them — live in the tier's git history. Three fact files retired; the skill and
command descriptions cost ~140 B of always-on context between them.
