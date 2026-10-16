# Brief: owner inventory and a per-fact existence answer at the memory gate

From a handoff session, 2026-10-15. Input for gitlore, not a decision: the
options below carry the evidence, and the choice is my human partner's.

## Evidence

`/Users/david/code/handoff/plans/reports/2026-10-12-memory-approval-redirections.md`
measured every memory approval round in gitlore-using repositories,
2026-06-22 to 2026-10-12: 243 rounds, 33 (14%) with a destination redirected
by my human partner, 14 (6%) with a fact rejected outright. A blind Sonnet
reviewer holding only the written rules matched 17 of 26 fact-to-skill moves
and 0 of 10 fact-to-tool/hook/template moves, and reproduced almost none of
the rejections. Its recommendation, decided 2026-10-15: no general memory
reviewer. The two levers it names both live in gitlore.

## 1. What the owners list lacks is inventory, not principle

`skills/memory-writing/SKILL.md` §1 question 2 lists "a hook or tool that
prints the diagnosis" as an owner (checked against the source, 2026-10-15). It
does not say:

- which tools, hooks, plugins and agents exist as owners, that my human
  partner owns them, and that a fix there is preferred to a note;
- that a brief dropped in the owning repository's `inbox/` is a destination in
  its own right, with or without a pointer left in memory;
- that agent definitions and skill bodies in sibling repositories can hold a
  fact (the reviewer saw only skill names and descriptions).

The missed redirections in the report's "What the missed redirections had in
common" section are of these kinds (R052, R081, R161, R184, R222, R223b, R226,
R234, R237 for fix-at-source; R194, R214, R221 for sibling artifacts).

Options for where the inventory lives:

- (a) The skill body names the route (brief into the owner's `inbox/`) and
  the shape of the inventory, and points to a shared-tier fact holding the
  list itself, so the list is maintained where facts are. Costs one index
  line in a store already past the loader's truncation size in some repos.
- (b) The skill body names the route and tells the pass to list the sibling
  repositories' plugins, hooks and agents at the gate rather than holding a
  list. No drift; costs calls per gate.
- (c) The route alone, no inventory.

## 2. The rejections came from a question asked of a named fact

All 14 rejections rest on questions §1 already asks (is there an incident,
would the reader reach it unaided). The agent at the gate runs the skill and
still does not answer "discard"; six replies in the corpus that name the rules
to the agent were enough for it to withdraw the fact. The report reads this as
the rule text not producing the verdict until it is applied to a named fact by
someone who doubts it.

Option: the approval clause (`reference/memory-approval-clause.txt`) asks the
summary's **New** paragraph to state, per fact, the incident and why a reader
would not reach it unaided — beside "what prompted writing it now", which
covers the first half only. Untested; the report flags it as such. handoff's
checkpoint wraps this clause verbatim, so a change here reaches handoff-driven
gates with no change in handoff.
