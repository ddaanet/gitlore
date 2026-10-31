# Owners outside this repo

Question 2 of the skill asks whether another artifact owns the fact. The owner
is often a sibling project, and whether it is one is not visible from this
repo's files. The inventory says which projects my human partner owns and
therefore may route a fix to.

## Reading the inventory

The inventory is the fact `owned-projects.md` at the root of each mounted
shared tier. It has no index line, so recall never surfaces it; the pass reads
it by name. Resolve the paths the way the scripts do:

1. `<mempath>` is
   `git config --file .gitmodules submodule.gitlore-memory.path`.
2. The mounted tiers are the lines of `<mempath>/.gitlore-tiers`.
3. Read `<mempath>/<tier>/owned-projects.md` for each; a tier without the file
   is skipped.

Read it at question 2, before settling on a destination. A project present in
the inventory is modifiable by its own session.

## What an owner can be

A sibling project's owning artifact includes its skill bodies and agent
definitions, not only the skill name and description that an installed-skill
listing shows. A fact about how a skill behaves belongs in that skill's body;
one about how an agent behaves, in its definition.

## Where the fact goes

- **This repo owns it:** fix the owner. A fix at the owner is preferred to a
  note, and the fact then leaves the store.
- **A sibling owns it and the inventory lists it:** a brief dropped in that
  repository's `inbox/` is a destination in its own right, with or without a
  pointer left in memory. Other repositories are read-only beyond that brief.
- **The inventory has no row for the owner:** at the commit review, and only
  there, ask my human partner whether that project is modifiable. Record the
  answer by adding a row to the tier's `owned-projects.md` in the same memory
  change, so the next gate does not ask again.
