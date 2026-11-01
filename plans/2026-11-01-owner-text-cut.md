# Cut the memory-writing hub to acts — plan

Status: done. Base: `dev`. One commit, shown to my human partner as a diff
before it lands.

Edits 1 and 2 are approved wording: write them verbatim. Edit 4 is a contract.

## Contract

- Pre: the only inbound links to `owners.md` and `owner-inventory.md` are inside
  the skill and at `docs/references/memory-authoring-guidance.md:146` (grepped
  2026-11-01). The routing rules dropped from the skill are stated in the
  ddaanet tier's `owned-projects.md` (read 2026-11-01).
- Post: `skills/memory-writing/SKILL.md` is under 9500 bytes, with Q2's owners
  and the skill-override paragraph inside it. `references/owners.md` and
  `references/owner-inventory.md` are gone and nothing links to either.
  `just check-size`, `just check-refs` and `tools/check-docs-links.py` pass.
- Invariant: frontmatter, §8 and every string the suites grep in the hub are
  untouched. Every rule the hub states survives as an act. D69's conclusion line
  and number are unchanged.
- Gate: `just precommit`, plus `plugin-dev/run-bats.sh` on
  `tests/plugin_distribution.bats`, `tests/plugin_distribution_commands.bats`
  and `tests/cc_hook_index_compose_notices.bats` run directly, since the gate
  caches its suites on skill prose.

## Edits

1. Replace hub Q2 (`SKILL.md:40–49`) with:

   ```markdown
   2. **Does another artifact own it?** Move the fact to its owner even when the
      memory is accurate, and grep the owner for the load-bearing terms before
      accepting that it covers the fact:
      - **A skill:** the fact reduces to "when using \<skill\>, do X". Delete it; if
        the skill lacks X, fix the skill.
      - **A design doc:** a decision, a supersession, a dated status. Record it in the
        living design doc.
      - **The code:** how one call site must behave. Write it as a comment at that
        site.
      - **CLAUDE.md or a shared tier's conventions file:** a convention binding all
        work in one repo or tier. A fact meant to be found on meeting a symptom stays
        in memory.
      - **A hook or tool that prints the diagnosis when it fires:** delete a memory
        that restates its output; when the output lacks it, fix the output.
      - **A sibling project's skill body or agent definition:** read
        `<mempath>/<tier>/owned-projects.md` for each line of
        `<mempath>/.gitlore-tiers`, where `<mempath>` is
        `git config --file .gitmodules submodule.gitlore-memory.path`, skipping a tier
        without the file, and route the fact as the inventory says.
   ```

2. Replace §7's closing pointer to `owners.md` (`SKILL.md:162–163`) with:

   ```markdown
   A fact written to override an installed skill sits on that skill's topic, so a
   coverage scan flags it as owned: check which way the claim points before
   counting the skill as its owner.
   ```

3. Delete `references/owners.md` and `references/owner-inventory.md`.
4. Cut the rest of the hub to acts, following `craft:directive-writing`: delete
   mechanism, rationale and restatement a reader cannot act on, and keep one
   clause where its absence would lead a reader to the wrong verdict. A rule
   whose only statement is its rationale is rewritten as the act, not deleted.
   Pointers to the remaining `references/` nodes keep their moments.
5. In `memory-authoring-guidance.md:145–146`, "The detail is the skill's
   `references/owner-inventory.md`." points instead at the tier's
   `owned-projects.md` for routing and at the skill's Q2 for locating it.

## Scope note

The rule to ask about an unlisted project at the commit review and record a row
then lives only in each tier's `owned-projects.md`; a tier whose inventory does
not state it loses it. Accepted with the cut.
